#!/usr/bin/env bash
set -euo pipefail

if ! command -v railway >/dev/null 2>&1; then
  npm install -g @railway/cli
fi

: "${RAILWAY_API_TOKEN:?RAILWAY_API_TOKEN must be set in CCE secrets}"
: "${MCP_BASE_SECRET:?MCP_BASE_SECRET must be set in CCE secrets}"
: "${CF_API_TOKEN:?CF_API_TOKEN must be set in CCE secrets}"
: "${CF_ACCOUNT_ID:?CF_ACCOUNT_ID must be set in CCE secrets}"
: "${CF_ZONE_ID:?CF_ZONE_ID must be set in CCE secrets}"
: "${CF_DOMAIN:?CF_DOMAIN must be set in CCE secrets}"

chmod +x "$(pwd)/scripts/derive-token.sh" "$(pwd)/scripts/provision-cf-tunnel.sh"
railway whoami
