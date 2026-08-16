#!/bin/sh
set -eu

origin="${1:-https://deriv.wtf}"

for route in / /root-space/ /mint/ /holders/ /protocol/ /mobile/ /healthz /version.json /robots.txt /sitemap.xml; do
  code="$(curl --silent --show-error --location --output /dev/null --write-out '%{http_code}' "${origin}${route}")"
  if [ "$code" != "200" ]; then
    echo "FAIL ${route}: HTTP ${code}" >&2
    exit 1
  fi
  echo "ok ${route}: HTTP ${code}"
done

missing_code="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' "${origin}/definitely-not-a-route")"
test "$missing_code" = "404" || { echo "FAIL missing route: HTTP ${missing_code}" >&2; exit 1; }
echo "ok missing route: HTTP 404"

post_code="$(curl --silent --show-error --request POST --output /dev/null --write-out '%{http_code}' "${origin}/")"
test "$post_code" = "405" || { echo "FAIL POST guard: HTTP ${post_code}" >&2; exit 1; }
echo "ok POST guard: HTTP 405"

headers="$(curl --silent --show-error --head "${origin}/")"
for header in strict-transport-security content-security-policy x-content-type-options x-frame-options referrer-policy permissions-policy; do
  printf '%s' "$headers" | grep -qi "^${header}:" || { echo "FAIL missing ${header}" >&2; exit 1; }
  echo "ok header: ${header}"
done
