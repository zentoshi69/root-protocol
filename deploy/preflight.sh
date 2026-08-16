#!/usr/bin/env bash
#
# HoodPups — VPS preflight. READ ONLY. Changes nothing.
#
# Run this ON srv1505584 BEFORE `deploy.sh`. It proves, with live commands, the facts the deploy
# depends on. Nothing here is asserted from memory, because every past incident on this box traces
# to a value someone remembered rather than checked.
#
# It exits non-zero and refuses to proceed if:
#   - the live edge container is not running
#   - `import tenants/*.caddy` is missing from the edge config (that is an incident, not a deploy)
#   - a host proxy is active on 80/443 (two proxies fighting takes every site down)
#   - any identifier this stack wants is already taken
#
#   sudo ./deploy/preflight.sh
#
set -uo pipefail

EDGE_CONTAINER="deploy-caddy-1"
EDGE_DIR="/opt/finetrader/release/deploy"
APP="hoodpups"
DOMAIN="${HOODPUPS_DOMAIN:-}"

RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; RST=$'\033[0m'
FAIL=0
ok()   { echo "${GRN}  ok  ${RST} $*"; }
bad()  { echo "${RED} FAIL ${RST} $*"; FAIL=1; }
warn() { echo "${YLW} warn ${RST} $*"; }

echo "=== HoodPups preflight — read only, changes nothing ==="
echo

# ---------------------------------------------------------------- 1. the edge
echo "1. The live edge"
if docker ps --format '{{.Names}}' | grep -qx "$EDGE_CONTAINER"; then
  ok "$EDGE_CONTAINER is running"
else
  bad "$EDGE_CONTAINER is NOT running — stop, this is an incident, not a deploy"
fi

EDGE_NET="$(docker inspect "$EDGE_CONTAINER" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null | tr ' ' '\n' | grep -v '^$' | head -1)"
if [ -n "${EDGE_NET:-}" ]; then
  ok "edge network: ${EDGE_NET}"
else
  bad "could not read the edge network — do NOT guess it"
fi

if docker exec "$EDGE_CONTAINER" sh -c 'cat /etc/caddy/Caddyfile' 2>/dev/null | grep -q 'import tenants/\*\.caddy'; then
  ok "'import tenants/*.caddy' present — the sanctioned extension point is intact"
else
  bad "'import tenants/*.caddy' MISSING from the edge Caddyfile — STOP. Writing anywhere else gets wiped by the next FINE TRADER deploy, or breaks their config."
fi

if [ -d "$EDGE_DIR/tenants" ]; then
  ok "tenants dir exists: $EDGE_DIR/tenants ($(ls -1 "$EDGE_DIR/tenants" 2>/dev/null | wc -l) existing tenant files)"
else
  bad "$EDGE_DIR/tenants does not exist"
fi
echo

# ------------------------------------------------- 2. no second proxy on host
echo "2. No competing proxy on the host"
for svc in caddy nginx apache2; do
  state="$(systemctl is-active "$svc" 2>/dev/null || true)"
  if [ "$state" = "active" ]; then
    bad "host $svc is ACTIVE — it will fight the container for 80/443. Stop and disable it before deploying."
  else
    ok "host $svc not active (${state:-absent})"
  fi
done

PORT_OWNERS="$(ss -tulpn 2>/dev/null | grep -E ':(80|443)\b' || true)"
if [ -n "$PORT_OWNERS" ] && ! echo "$PORT_OWNERS" | grep -qv 'docker-proxy'; then
  ok "80/443 owned by docker-proxy only"
elif [ -z "$PORT_OWNERS" ]; then
  warn "nothing listening on 80/443 — unexpected; check the edge is really up"
else
  bad "something other than docker-proxy owns 80/443:"; echo "$PORT_OWNERS" | sed 's/^/        /'
fi
echo

# ------------------------------------------------------- 3. identifier safety
# This stack publishes NO host ports — it joins the edge network and Caddy reaches it by container
# name. That removes host-port collision from the problem entirely. What remains to check is names.
echo "3. Identifiers this stack wants (none of them host ports — nothing is published)"
for n in "${APP}-web" "${APP}-relayer"; do
  if docker ps -a --format '{{.Names}}' | grep -qx "$n"; then
    bad "container name '$n' is ALREADY TAKEN"
    docker ps -a --filter "name=^${n}$" --format '        existing: {{.Names}} ({{.Image}}, {{.Status}})'
  else
    ok "container name '$n' is free"
  fi
done

if docker compose ls -a --format json 2>/dev/null | grep -q "\"Name\":\"${APP}\""; then
  bad "compose project '${APP}' already exists"
else
  ok "compose project '${APP}' is free"
fi

if docker network ls --format '{{.Name}}' | grep -qx "${APP}_internal"; then
  bad "network '${APP}_internal' already exists"
else
  ok "network '${APP}_internal' is free"
fi
echo

# ------------------------------------------------------------ 4. the domain
echo "4. Domain"
if [ -z "$DOMAIN" ]; then
  warn "HOODPUPS_DOMAIN not set — export it and re-run to check DNS and hostname collision"
else
  BOX_IP="$(curl -s --max-time 5 https://api.ipify.org || echo '')"
  DNS_IP="$(dig +short "$DOMAIN" 2>/dev/null | tail -1)"
  if [ -n "$BOX_IP" ] && [ "$DNS_IP" = "$BOX_IP" ]; then
    ok "$DOMAIN resolves to this box ($BOX_IP)"
  else
    bad "$DOMAIN resolves to '${DNS_IP:-nothing}', this box is '${BOX_IP:-unknown}' — TLS issuance will fail"
  fi

  # A duplicate hostname anywhere invalidates the ENTIRE Caddy config and downs every site.
  HITS="$(grep -rln "$DOMAIN" "$EDGE_DIR" 2>/dev/null || true)"
  if [ -z "$HITS" ]; then
    ok "$DOMAIN appears in no existing config — no hostname collision"
  else
    bad "$DOMAIN ALREADY APPEARS in the edge config. A duplicate hostname invalidates the whole config and takes every site down:"
    echo "$HITS" | sed 's/^/        /'
  fi
fi
echo

# ------------------------------------------------------------- 5. blast radius
echo "5. Current live sites (baseline for the post-deploy check)"
if [ -d "$EDGE_DIR/tenants" ]; then
  grep -rhoE '^[a-z0-9.-]+\.[a-z]{2,}' "$EDGE_DIR/tenants" 2>/dev/null | sort -u | sed 's/^/        /' || true
fi
grep -rhoE '^[a-z0-9.-]+\.[a-z]{2,}' "$EDGE_DIR/Caddyfile" 2>/dev/null | sort -u | sed 's/^/        /' || true
echo

echo "=== result ==="
if [ "$FAIL" -eq 0 ]; then
  echo "${GRN}PASS${RST} — safe to run deploy.sh"
  echo
  echo "Export these before deploying:"
  echo "  export EDGE_NET=${EDGE_NET}"
  echo "  export HOODPUPS_DOMAIN=${DOMAIN:-<your-domain>}"
  exit 0
fi
echo "${RED}FAIL${RST} — do NOT deploy. Fix the items above first."
exit 1
