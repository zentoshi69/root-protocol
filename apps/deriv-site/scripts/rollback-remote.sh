#!/bin/sh
set -eu

state_dir="/opt/deriv.wtf"
container="deriv-wtf-site"
previous_release="$(sed -n '1p' "${state_dir}/PREVIOUS_RELEASE")"
current_release="$(sed -n '1p' "${state_dir}/CURRENT_RELEASE")"

case "$previous_release" in
  *[!A-Za-z0-9._-]*|'') echo "invalid or missing previous release" >&2; exit 2 ;;
esac

docker image inspect "deriv-wtf:${previous_release}" >/dev/null
docker rm --force "$container" >/dev/null 2>&1 || true
docker run --detach \
  --name "$container" \
  --network deploy_default \
  --network-alias "$container" \
  --restart unless-stopped \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=16m,uid=101,gid=101 \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --pids-limit 100 \
  --memory 128m \
  --cpus 0.50 \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  "deriv-wtf:${previous_release}" >/dev/null

attempt=0
while test "$attempt" -lt 20; do
  health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container")"
  test "$health" = "healthy" && break
  test "$health" = "unhealthy" && { docker logs --tail 100 "$container" >&2; exit 1; }
  attempt=$((attempt + 1))
  sleep 2
done
test "$health" = "healthy"

printf '%s\n' "$previous_release" > "${state_dir}/CURRENT_RELEASE"
printf '%s\n' "$current_release" > "${state_dir}/PREVIOUS_RELEASE"
echo "rolled back to deriv-wtf:${previous_release}"
