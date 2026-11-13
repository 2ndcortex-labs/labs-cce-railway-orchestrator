#!/usr/bin/env bash
set -euo pipefail

PROJECT_SLUG="${1:?Usage: provision-cf-tunnel.sh <project-slug>}"
: "${SCL_CF_API_TOKEN:?SCL_CF_API_TOKEN must be set in CCE secrets}"
: "${SCL_CF_ACCOUNT_ID:?SCL_CF_ACCOUNT_ID must be set in CCE secrets}"
: "${SCL_CF_ZONE_ID:?SCL_CF_ZONE_ID must be set in CCE secrets}"
: "${SCL_CF_DOMAIN:?SCL_CF_DOMAIN must be set in CCE secrets}"

CLEAN_TOKEN=$(printf '%s' "${SCL_CF_API_TOKEN}" | tr -d '\r\n' | sed -E 's/^[[:space:]"'"'"']+//; s/[[:space:]"'"'"']+$//; s/^Bearer[[:space:]]+//I')
CLEAN_DOMAIN=$(printf '%s' "${SCL_CF_DOMAIN}" | tr -d '\r\n ' | sed -E 's/^\*\.//')

TUNNEL_NAME="rw-${PROJECT_SLUG}"
HOSTNAME="${PROJECT_SLUG}.${CLEAN_DOMAIN}"
CF_API="https://api.cloudflare.com/client/v4"

EXISTING_ID=$(curl -fsSL "${CF_API}/accounts/${SCL_CF_ACCOUNT_ID}/cfd_tunnel?name=${TUNNEL_NAME}&is_deleted=false" \
  -H "Authorization: Bearer ${CLEAN_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.result[0].id // empty')

if [ -n "${EXISTING_ID}" ] && [ "${EXISTING_ID}" != "null" ]; then
  TUNNEL_ID="${EXISTING_ID}"
else
  TUNNEL_SECRET=$(openssl rand -base64 32)
  CREATE_RESP=$(curl -fsSL -X POST "${CF_API}/accounts/${SCL_CF_ACCOUNT_ID}/cfd_tunnel" \
    -H "Authorization: Bearer ${CLEAN_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "{\"name\":\"${TUNNEL_NAME}\",\"tunnel_secret\":\"${TUNNEL_SECRET}\",\"config_src\":\"cloudflare\"}")
  TUNNEL_ID=$(printf "%s" "${CREATE_RESP}" | jq -r '.result.id // empty')
  if [ -z "${TUNNEL_ID}" ] || [ "${TUNNEL_ID}" = "null" ]; then
    echo "ERROR: Failed to create Cloudflare Tunnel: ${CREATE_RESP}" >&2
    exit 1
  fi
fi

curl -fsSL -X PUT "${CF_API}/accounts/${SCL_CF_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" \
  -H "Authorization: Bearer ${CLEAN_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "{\"config\":{\"ingress\":[{\"hostname\":\"${HOSTNAME}\",\"service\":\"http://127.0.0.1:8080\"},{\"service\":\"http_status:404\"}]}}" >/dev/null

DNS_RECORD_ID=$(curl -fsSL "${CF_API}/zones/${SCL_CF_ZONE_ID}/dns_records?type=CNAME&name=${HOSTNAME}" \
  -H "Authorization: Bearer ${CLEAN_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.result[0].id // empty')

DNS_PAYLOAD="{\"type\":\"CNAME\",\"name\":\"${HOSTNAME}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"proxied\":true}"

if [ -n "${DNS_RECORD_ID}" ] && [ "${DNS_RECORD_ID}" != "null" ]; then
  curl -fsSL -X PUT "${CF_API}/zones/${SCL_CF_ZONE_ID}/dns_records/${DNS_RECORD_ID}" \
    -H "Authorization: Bearer ${CLEAN_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "${DNS_PAYLOAD}" >/dev/null
else
  curl -fsSL -X POST "${CF_API}/zones/${SCL_CF_ZONE_ID}/dns_records" \
    -H "Authorization: Bearer ${CLEAN_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "${DNS_PAYLOAD}" >/dev/null
fi

CF_TUNNEL_TOKEN=$(curl -fsSL "${CF_API}/accounts/${SCL_CF_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/token" \
  -H "Authorization: Bearer ${CLEAN_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.result // empty')

if [ -z "${CF_TUNNEL_TOKEN}" ] || [ "${CF_TUNNEL_TOKEN}" = "null" ]; then
  echo "ERROR: Failed to fetch Cloudflare Tunnel token for ${TUNNEL_ID}" >&2
  exit 1
fi

printf "%s\n" "${CF_TUNNEL_TOKEN}"
