#!/usr/bin/env bash
set -euo pipefail

PROJECT_SLUG="${1:?Usage: provision-cf-tunnel.sh <project-slug>}"
: "${CF_API_TOKEN:?CF_API_TOKEN must be set in CCE secrets}"
: "${CF_ACCOUNT_ID:?CF_ACCOUNT_ID must be set in CCE secrets}"
: "${CF_ZONE_ID:?CF_ZONE_ID must be set in CCE secrets}"
: "${CF_DOMAIN:?CF_DOMAIN must be set in CCE secrets}"

TUNNEL_NAME="rw-${PROJECT_SLUG}"
HOSTNAME="${PROJECT_SLUG}.${CF_DOMAIN}"
CF_API="https://api.cloudflare.com/client/v4"

EXISTING_ID=$(curl -fsSL "${CF_API}/accounts/${CF_ACCOUNT_ID}/cfd_tunnel?name=${TUNNEL_NAME}&is_deleted=false" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.result[0].id // empty')

if [ -n "${EXISTING_ID}" ]; then
  TUNNEL_ID="${EXISTING_ID}"
else
  TUNNEL_SECRET=$(openssl rand -base64 32)
  TUNNEL_ID=$(curl -fsSL -X POST "${CF_API}/accounts/${CF_ACCOUNT_ID}/cfd_tunnel" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "{\"name\":\"${TUNNEL_NAME}\",\"tunnel_secret\":\"${TUNNEL_SECRET}\",\"config_src\":\"cloudflare\"}" \
    | jq -r '.result.id')
fi

curl -fsSL -X PUT "${CF_API}/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "{\"config\":{\"ingress\":[{\"hostname\":\"${HOSTNAME}\",\"service\":\"http://127.0.0.1:8080\"},{\"service\":\"http_status:404\"}]}}" >/dev/null

DNS_RECORD_ID=$(curl -fsSL "${CF_API}/zones/${CF_ZONE_ID}/dns_records?type=CNAME&name=${HOSTNAME}" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.result[0].id // empty')

DNS_PAYLOAD="{\"type\":\"CNAME\",\"name\":\"${HOSTNAME}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"proxied\":true}"

if [ -n "${DNS_RECORD_ID}" ]; then
  curl -fsSL -X PUT "${CF_API}/zones/${CF_ZONE_ID}/dns_records/${DNS_RECORD_ID}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "${DNS_PAYLOAD}" >/dev/null
else
  curl -fsSL -X POST "${CF_API}/zones/${CF_ZONE_ID}/dns_records" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "${DNS_PAYLOAD}" >/dev/null
fi

CF_TUNNEL_TOKEN=$(curl -fsSL "${CF_API}/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/token" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.result')

printf "%s\n" "${CF_TUNNEL_TOKEN}"
