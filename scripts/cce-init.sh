#!/usr/bin/env bash
set -euo pipefail

export PATH="/workspace/.onboarding/bin:${HOME}/.local/bin:${PATH}"

MODE="check"
STRICT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)
      MODE="${2:?Missing value for --mode}"
      shift 2
      ;;
    --strict)
      STRICT=1
      shift
      ;;
    check|operate|bootstrap)
      MODE="$1"
      shift
      ;;
    *)
      echo "Usage: $0 [--mode check|operate|bootstrap] [--strict]" >&2
      exit 2
      ;;
  esac
done

missing_shared=()
missing_admin=()

check_var() {
  local var_name="$1"
  local group="$2"
  local desc="$3"
  local val="${!var_name:-}"

  if [ -z "${val}" ]; then
    if [ "${group}" = "shared" ]; then
      missing_shared+=("  - ${var_name}:${desc}")
    else
      missing_admin+=("  - ${var_name}:${desc}")
    fi
  elif [[ "${val}" == CODEX_NET_SECRET* ]] && [[ "${var_name}" =~ ^(RAILWAY_API_TOKEN\vert{}CF_API_TOKEN\vert{}MCP_BASE_SECRET\vert{}CLAUDE_CODE_OAUTH_TOKEN)$ ]]; then
    missing_admin+=("  - ${var_name}: Set as 'Network secret' placeholder; move to 'Environment variable' in Personal Vault")
  fi
}

check_var "CF_DOMAIN"               "shared" "Shared Cloud Environment -> Environment variables (e.g. mytunnels.fyi)"
check_var "CF_ACCESS_CLIENT_ID"     "shared" "Shared Cloud Environment -> Environment variables"
check_var "CF_ACCESS_CLIENT_SECRET" "shared" "Shared Cloud Environment -> Network secrets (*.mytunnels.fyi) or Environment variables"

check_var "MCP_BASE_SECRET"         "admin"  "Personal Vault -> Environment variables (openssl rand -hex 32)"
check_var "CLAUDE_CODE_OAUTH_TOKEN" "admin"  "Personal Vault -> Environment variables (claude setup-token)"
check_var "CF_ACCOUNT_ID"           "admin"  "Personal Vault -> Environment variables"
check_var "CF_ZONE_ID"              "admin"  "Personal Vault -> Environment variables"
check_var "CF_API_TOKEN"            "admin"  "Personal Vault -> Environment variables (Cloudflare API Token)"
check_var "RAILWAY_API_TOKEN"       "admin"  "Personal Vault -> Environment variables (Railway API Token)"

echo "================================
