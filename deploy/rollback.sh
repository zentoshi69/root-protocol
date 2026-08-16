#!/usr/bin/env bash
#
# HoodPups — remove this stack, leaving every other site exactly as it was.
#
# Only ever removes OUR tenant file and OUR containers. The main Caddyfile and every other tenant
# file are untouched in every branch. That property is what makes rolling back safe to do quickly
# rather than something to deliberate over.
#
#   sudo ./deploy/rollback.sh
#
set -euo pipefail

EDGE_CONTAINER="deploy-caddy-1"
TENANT_FILE="/opt/finetrader/release/deploy/tenants/hoodpups.caddy"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Removing the HoodPups tenant file (ours only)"
rm -f "$TENANT_FILE"

echo "==> Validating the remaining config BEFORE reloading"
docker exec "$EDGE_CONTAINER" caddy validate --config /etc/caddy/Caddyfile

echo "==> Reloading the edge (zero downtime)"
docker exec "$EDGE_CONTAINER" caddy reload --config /etc/caddy/Caddyfile

echo "==> Stopping the HoodPups stack"
docker compose -f "$HERE/docker-compose.yml" down --remove-orphans || true

echo "==> Confirming other sites are still up"
for site in $(grep -rhoE '^[a-z0-9.-]+\.[a-z]{2,}' /opt/finetrader/release/deploy/Caddyfile /opt/finetrader/release/deploy/tenants/*.caddy 2>/dev/null | sort -u); do
  printf '    %-40s ' "https://${site}"
  curl -sSI --max-time 10 "https://${site}" 2>&1 | head -1 || echo "NO RESPONSE — INVESTIGATE"
done

echo
echo "Rolled back. The main Caddyfile and all other tenant files were never touched."
