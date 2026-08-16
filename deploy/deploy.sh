#!/usr/bin/env bash
#
# HoodPups — deploy to srv1505584 without disturbing anything already running.
#
# Ordering is the safety mechanism, not care:
#   preflight (read-only)  →  bring up the app  →  confirm the edge can reach it
#   →  write ONE new tenant file  →  VALIDATE  →  reload (never restart)  →  blast-radius check
#
# Two rules that are non-negotiable on this box:
#   * `caddy validate` must print a valid configuration BEFORE any reload. A duplicate hostname or a
#     paste-poisoned URL invalidates the whole config and downs every site.
#   * `reload`, never `restart`. A restart drops every site for its duration; reload is zero-downtime.
#
# Rollback is two commands and only ever removes OUR file. See rollback.sh.
#
#   sudo ./deploy/preflight.sh
#   export EDGE_NET=<from preflight>  HOODPUPS_DOMAIN=<your domain>
#   sudo ./deploy/deploy.sh
#
set -euo pipefail

EDGE_CONTAINER="deploy-caddy-1"
EDGE_DIR="/opt/finetrader/release/deploy"
TENANT_FILE="$EDGE_DIR/tenants/hoodpups.caddy"
APP="hoodpups"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${EDGE_NET:?EDGE_NET must be exported from preflight.sh output — never guessed}"
: "${HOODPUPS_DOMAIN:?HOODPUPS_DOMAIN must be exported}"

RED=$'\033[31m'; GRN=$'\033[32m'; RST=$'\033[0m'
step() { echo; echo "${GRN}==>${RST} $*"; }
die()  { echo "${RED}!! $*${RST}" >&2; exit 1; }

step "0. Preflight (read-only)"
"$HERE/preflight.sh" || die "preflight failed — not deploying"

step "1. Bring up the app stack (publishes no host ports)"
docker compose -f "$HERE/docker-compose.yml" up -d --build 2>&1 | tee /tmp/hoodpups-up.log
# Compose recreating something we did not define means a name collision with another stack.
if grep -qiE 'recreat' /tmp/hoodpups-up.log && ! grep -qiE 'recreat.*hoodpups-' /tmp/hoodpups-up.log; then
  die "compose recreated a container this stack does not define — name collision, investigate before continuing"
fi

step "2. Confirm the edge can actually reach the app"
docker inspect "${APP}-web" --format '{{json .NetworkSettings.Networks}}' | tr ',' '\n' | grep -q "$EDGE_NET" \
  || die "${APP}-web is not attached to $EDGE_NET — Caddy would 502"
docker exec "$EDGE_CONTAINER" sh -c "wget -qO- --timeout=5 http://${APP}-web:8080/healthz >/dev/null 2>&1" \
  || die "edge container cannot reach ${APP}-web:8080 — fix before touching Caddy config"
echo "    edge -> ${APP}-web:8080 reachable"

step "3. Hostname collision check (a duplicate downs EVERY site, not just ours)"
EXISTING="$(grep -rln "$HOODPUPS_DOMAIN" "$EDGE_DIR" 2>/dev/null || true)"
if [ -n "$EXISTING" ] && [ "$EXISTING" != "$TENANT_FILE" ]; then
  die "$HOODPUPS_DOMAIN already appears in: $EXISTING"
fi
echo "    $HOODPUPS_DOMAIN is unused"

step "4. Write ONE new tenant file (zero existing files touched)"
mkdir -p "$EDGE_DIR/tenants"
sed "s|__DOMAIN__|${HOODPUPS_DOMAIN}|g" "$HERE/tenants/hoodpups.caddy.template" > "$TENANT_FILE"
echo "    wrote $TENANT_FILE — reading it back:"
sed 's/^/        /' "$TENANT_FILE" | head -8

step "5. Confirm the file is visible inside the container"
# The tenants directory is bind-mounted; a single-file mount would not propagate.
docker exec "$EDGE_CONTAINER" ls /etc/caddy/tenants/hoodpups.caddy >/dev/null \
  || die "tenant file not visible inside $EDGE_CONTAINER — check the bind mount"
echo "    visible"

step "6. VALIDATE before reloading — this is the gate"
if ! docker exec "$EDGE_CONTAINER" caddy validate --config /etc/caddy/Caddyfile 2>&1 | tee /tmp/hoodpups-validate.log | grep -qi 'valid config'; then
  cat /tmp/hoodpups-validate.log
  rm -f "$TENANT_FILE"
  die "config INVALID — tenant file removed, nothing reloaded, all sites untouched"
fi
echo "    valid configuration"

step "7. Reload (zero downtime — never restart the edge)"
docker exec "$EDGE_CONTAINER" caddy reload --config /etc/caddy/Caddyfile
echo "    reloaded"

step "8. Blast-radius check — the new site AND the existing ones"
echo "    waiting 10s for certificate issuance to begin..."
sleep 10
printf '    %-40s ' "https://${HOODPUPS_DOMAIN}"
curl -sSI --max-time 20 "https://${HOODPUPS_DOMAIN}" 2>&1 | head -1 || echo "no response yet (first cert can take ~60s — do NOT roll back a valid config over a cert race)"

for site in $(grep -rhoE '^[a-z0-9.-]+\.[a-z]{2,}' "$EDGE_DIR/Caddyfile" "$EDGE_DIR"/tenants/*.caddy 2>/dev/null | sort -u | grep -v "^${HOODPUPS_DOMAIN}$"); do
  printf '    %-40s ' "https://${site}"
  curl -sSI --max-time 10 "https://${site}" 2>&1 | head -1 || echo "${RED}NO RESPONSE — INVESTIGATE${RST}"
done

step "9. Record the allocation"
mkdir -p /root/infra
LINE="$(date -u +%Y-%m-%d) | hoodpups | hoodpups-web | net:${EDGE_NET} | ports:none-published | ${HOODPUPS_DOMAIN} | ${TENANT_FILE}"
grep -qF "hoodpups" /root/infra/ALLOCATIONS.md 2>/dev/null || echo "$LINE" >> /root/infra/ALLOCATIONS.md
echo "    $LINE"

echo
echo "${GRN}Done.${RST} Rollback if needed: ./deploy/rollback.sh"
