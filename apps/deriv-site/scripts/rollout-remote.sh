#!/bin/sh
set -eu

build_id="${1:?usage: rollout-remote.sh <build-id>}"
case "$build_id" in
  *[!A-Za-z0-9._-]*|'') echo "invalid build id" >&2; exit 2 ;;
esac

release_dir="/opt/deriv.wtf/releases/${build_id}"
state_dir="/opt/deriv.wtf"
tenant_file="/opt/finetrader/release/deploy/tenants/deriv-wtf.caddy"
tenant_backup="${state_dir}/deriv-wtf.caddy.previous"
image="deriv-wtf:${build_id}"
container="deriv-wtf-site"
network="deploy_default"

test -f "${release_dir}/Dockerfile"
test -f "${release_dir}/nginx.conf"
test -f "${release_dir}/edge.caddy"
test -f "${release_dir}/public/index.html"

mkdir -p "$state_dir"

docker build --pull=false --tag "$image" "$release_dir"

previous_release=""
if test -f "${state_dir}/CURRENT_RELEASE"; then
  previous_release="$(sed -n '1p' "${state_dir}/CURRENT_RELEASE")"
fi

if docker container inspect "$container" >/dev/null 2>&1; then
  docker stop --time 15 "$container" >/dev/null
  docker rm "$container" >/dev/null
fi

start_container() {
  selected_image="$1"
  docker run --detach \
    --name "$container" \
    --network "$network" \
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
    "$selected_image" >/dev/null
}

restore_previous() {
  docker rm --force "$container" >/dev/null 2>&1 || true
  if test -n "$previous_release" && docker image inspect "deriv-wtf:${previous_release}" >/dev/null 2>&1; then
    start_container "deriv-wtf:${previous_release}"
  fi
}

start_container "$image"

healthy=""
attempt=0
while test "$attempt" -lt 20; do
  health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container")"
  if test "$health" = "healthy"; then
    healthy=1
    break
  fi
  if test "$health" = "unhealthy" || test "$health" = "exited" || test "$health" = "dead"; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 2
done

if test -z "$healthy"; then
  docker logs --tail 100 "$container" >&2 || true
  restore_previous
  echo "new container failed its health check; previous release restored" >&2
  exit 1
fi

docker exec "$container" wget -q -O - http://127.0.0.1:8080/version.json

if test -f "$tenant_file"; then
  cp "$tenant_file" "$tenant_backup"
else
  : > "$tenant_backup"
fi
cp "${release_dir}/edge.caddy" "$tenant_file"

if ! docker exec deploy-caddy-1 caddy validate --config /etc/caddy/Caddyfile; then
  if test -s "$tenant_backup"; then cp "$tenant_backup" "$tenant_file"; else rm -f "$tenant_file"; fi
  restore_previous
  echo "edge validation failed; previous release restored" >&2
  exit 1
fi

if ! docker exec deploy-caddy-1 caddy reload --config /etc/caddy/Caddyfile; then
  if test -s "$tenant_backup"; then cp "$tenant_backup" "$tenant_file"; else rm -f "$tenant_file"; fi
  docker exec deploy-caddy-1 caddy reload --config /etc/caddy/Caddyfile || true
  restore_previous
  echo "edge reload failed; previous release restored" >&2
  exit 1
fi

if test -n "$previous_release"; then
  printf '%s\n' "$previous_release" > "${state_dir}/PREVIOUS_RELEASE"
fi
printf '%s\n' "$build_id" > "${state_dir}/CURRENT_RELEASE"

echo "deployed ${image}"
