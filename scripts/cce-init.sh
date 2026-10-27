#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---mode}"
if [ "${MODE}" = "--mode" ]; then
  MODE="${2:-check}"
fi

chmod +x "$(pwd)/scripts/derive-token.sh" "$(pwd)/scripts/provision-cf-tunnel.sh" 2>/dev/null || true

missing_shared=()
missing_admin=()

check_var() {
  local var_name="$1"
  local group="$2"
  local desc="$3"
  local val="${!var_name:-}"

  if [ -z "${val}" ]; then
    if [ "${group}" = "shared" ]; then
      missing_shared+=("  - ${var_name}: ${desc}")
    else
      missing_admin+=("  - ${var_name}: ${desc}")
    fi
  elif [[ "${val}" == CODEX_NET_SECRET* ]] && [[ "${var_name}" =~ ^(RAILWAY_API_TOKEN|CF_API_TOKEN|MCP_BASE_SECRET|CLAUDE_CODE_OAUTH_TOKEN)$ ]]; then
    missing_admin+=("  - ${var_name}: Currently set as 'Network secret' (placeholder detected). MUST be moved to 'Environment variable' in Personal Vault!")
  fi
}

# 1. Shared Environment Variables (Needed by everyone to connect to workers)
check_var "CF_DOMAIN"               "shared" "Set in Shared Cloud Environment -> Environment variables (e.g. yourdomain.com)"
check_var "CF_ACCESS_CLIENT_ID"     "shared" "Set in Shared Cloud Environment -> Environment variables (CF Service Token ID)"
check_var "CF_ACCESS_CLIENT_SECRET" "shared" "Set in Shared Cloud Environment -> Network secrets (Allowed domains: *.<CF_DOMAIN>) or Environment variables"

# 2. Admin / Provisioning Variables (Needed only when bootstrapping new Railway projects)
check_var "MCP_BASE_SECRET"         "admin"  "Set in Personal Vault -> Environment variables (64-char hex from: openssl rand -hex 32)"
check_var "CLAUDE_CODE_OAUTH_TOKEN" "admin"  "Set in Personal Vault -> Environment variables (from: claude setup-token)"
check_var "CF_ACCOUNT_ID"           "admin"  "Set in Personal Vault -> Environment variables (32-char Cloudflare Account ID)"
check_var "CF_ZONE_ID"              "admin"  "Set in Personal Vault -> Environment variables (32-char Cloudflare Zone ID)"
check_var "CF_API_TOKEN"            "admin"  "Set in Personal Vault -> Environment variables (Cloudflare API token with Tunnel:Edit + DNS:Edit)"
check_var "RAILWAY_API_TOKEN"       "admin"  "Set in Personal Vault -> Environment variables (Railway Account/Team token)"

echo "========================================================================"
echo " CCE Orchestrator Environment Pre-Flight Check (Mode: ${MODE})"
echo "========================================================================"

if [ ${#missing_shared[@]} -eq 0 ]; then
  echo "[OK] Shared Operator Environment Variables: READY"
else
  echo "[MISSING] Shared Cloud Environment Settings (Settings > Codex Cloud > Environments):"
  printf '%s\n' "${missing_shared[@]}"
fi

echo "------------------------------------------------------------------------"

if [ ${#missing_admin[@]} -eq 0 ]; then
  echo "[OK] Admin Bootstrap Personal Vault Variables: READY"
else
  echo "[MISSING/MISCONFIGURED] Admin Personal Vault Settings (Settings > Codex Cloud > Personal vault):"
  printf '%s\n' "${missing_admin[@]}"
  echo ""
  echo "  NOTE ON EGRESS PROXY: Keep a dummy Network Secret (e.g. ALLOWLIST_PROXY=1)"
  echo "  in your Cloud Environment with Allowed domains:"
  echo "    api.cloudflare.com, backboard.railway.com, *.railway.com, *.railway.app, *.<CF_DOMAIN>"
fi
echo "========================================================================"

if [ "${MODE}" = "check" ]; then
  exit 0
fi

if [ "${MODE}" = "operate" ]; then
  if [ ${#missing_shared[@]} -gt 0 ]; then
    echo "ERROR: Cannot operate worker until Shared Cloud Environment variables above are configured." >&2
    exit 1
  fi
  if [ -z "${MCP_BEARER_TOKEN:-}" ] && [ -z "${MCP_BASE_SECRET:-}" ]; then
    echo "ERROR: Operator requires either MCP_BEARER_TOKEN (teammate) or MCP_BASE_SECRET (admin) in Personal Vault -> Environment variables." >&2
    exit 1
  fi
  echo "Operator pre-flight passed."
  exit 0
fi

if [ "${MODE}" = "bootstrap" ]; then
  if [ ${#missing_shared[@]} -gt 0 ] || [ ${#missing_admin[@]} -gt 0 ]; then
    echo "ERROR: Cannot bootstrap new project until all missing variables above are set." >&2
    exit 1
  fi

  if ! command -v railway >/dev/null 2>&1; then
    npm install -g @railway/cli
  fi

  railway whoami
fi
