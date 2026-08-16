#!/bin/sh
set -eu

site_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
target="${DERIV_SSH_TARGET:-root@187.124.169.200}"
build_id="${1:-$(date -u +%Y%m%dT%H%M%SZ)}"

case "$build_id" in
  *[!A-Za-z0-9._-]*|'') echo "invalid build id" >&2; exit 2 ;;
esac

BUILD_ID="$build_id" node "${site_root}/scripts/build.mjs"
node "${site_root}/scripts/verify.mjs"

archive="$(mktemp /tmp/deriv-wtf-release.XXXXXX.tar.gz)"
trap 'rm -f "$archive"' EXIT HUP INT TERM

tar -C "$site_root" -czf "$archive" \
  Dockerfile nginx.conf edge.caddy public \
  scripts/rollout-remote.sh scripts/rollback-remote.sh scripts/smoke.sh

ssh "$target" "mkdir -p '/opt/deriv.wtf/releases/${build_id}'"
scp "$archive" "${target}:/opt/deriv.wtf/releases/${build_id}/release.tar.gz"
ssh "$target" "tar -xzf '/opt/deriv.wtf/releases/${build_id}/release.tar.gz' -C '/opt/deriv.wtf/releases/${build_id}' && chmod 0755 '/opt/deriv.wtf/releases/${build_id}/scripts/rollout-remote.sh' '/opt/deriv.wtf/releases/${build_id}/scripts/rollback-remote.sh' '/opt/deriv.wtf/releases/${build_id}/scripts/smoke.sh' && '/opt/deriv.wtf/releases/${build_id}/scripts/rollout-remote.sh' '${build_id}'"

echo "release ${build_id} installed on ${target}"
