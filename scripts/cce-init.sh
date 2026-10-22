#!/usr/bin/env bash

set -euo pipefail

if ! command -v railway >/dev/null 2>&1; then

  npm install -g @railway/cli

fi

: "${RAILWAY_API_TOKEN:?RAILWAY_API_TOKEN must be set in CCE secrets}"

chmod +x "$(pwd)/scripts/derive-token.sh"

railway whoami
