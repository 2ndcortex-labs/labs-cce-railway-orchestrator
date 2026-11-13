#!/usr/bin/env bash
set -euo pipefail

PROJECT_SLUG="${1:?Usage: derive-token.sh <project-slug>}"
: "${SCL_MCP_BASE_SECRET:?SCL_MCP_BASE_SECRET environment variable must be set in CCE}"

printf "%s" "${PROJECT_SLUG}" | openssl dgst -sha256 -hmac "${SCL_MCP_BASE_SECRET}" | awk '{print $NF}'
