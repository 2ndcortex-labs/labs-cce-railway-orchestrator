#!/usr/bin/env bash
set -euo pipefail

# Bridge SCL_RAILWAY_API_TOKEN to RAILWAY_API_TOKEN for native Railway CLI
if [ -n "${SCL_RAILWAY_API_TOKEN:-}" ]; then
  export RAILWAY_API_TOKEN="${SCL_RAILWAY_API_TOKEN}"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ONBOARDING_BIN="/workspace/.onboarding/bin"
LOCAL_BIN="${HOME}/.local/bin"

export PATH="${ONBOARDING_BIN}:${LOCAL_BIN}:${PATH}"

MODE="setup"
STRICT=0
SKIP_CLI=0
SKIP_VALIDATE=0

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
    --skip-cli)
      SKIP_CLI=1
      shift
      ;;
    --skip-validate)
      SKIP_VALIDATE=1
      shift
      ;;
    setup|check|operate|bootstrap)
      MODE="$1"
      shift
      ;;
    *)
      echo "Usage: $0 [--mode setup|check|operate|bootstrap] [--strict] [--skip-cli] [--skip-validate]" >&2
      exit 2
      ;;
  esac
done

echo "========================================================================"
echo " CCE Orchestrator Automated Setup & Pre-Flight (Mode: ${MODE})"
echo "========================================================================"

# 1. Persist PATH in ~/.bashrc and ~/.profile (Idempotent across restarts)
PATH_LINE='export PATH="/workspace/.onboarding/bin:${HOME}/.local/bin:${PATH}"'
for rc_file in "${HOME}/.bashrc" "${HOME}/.profile"; do
  if [ -f "${rc_file}" ]; then
    if ! grep -Fq "/workspace/.onboarding/bin" "${rc_file}" 2>/dev/null; then
      printf "\n# Added by cce-init.sh\n%s\n" "${PATH_LINE}" >> "${rc_file}"
    fi
  else
    printf "# Added by cce-init.sh\n%s\n" "${PATH_LINE}" > "${rc_file}"
  fi
done

# 2. Verify Node.js runtime (>=22 required; Node 24 is natively supported)
if command -v node >/dev/null 2>&1; then
  NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
  if [ "${NODE_MAJOR}" -ge 22 ]; then
    echo "[OK] Node.js Runtime: $(node -v) (>=22 supported; using native host runtime)"
  else
    echo "[ERROR] Node.js Runtime: $(node -v) found, but >=22 is required" >&2
    exit 1
  fi
else
  echo "[ERROR] Node.js Runtime: node not found on PATH" >&2
  exit 1
fi

# 3. Automated Railway CLI installation outside git checkout (Idempotent)
if [ "${SKIP_CLI}" -eq 0 ]; then
  if command -v railway >/dev/null 2>&1; then
    echo "[OK] Railway CLI: $(railway --version) ($(command -v railway))"
  else
    echo "[SETUP] Installing pinned Railway CLI outside git checkout..."
    if bash "${SCRIPT_DIR}/install-railway-cli.sh"; then
      echo "[OK] Railway CLI: $(railway --version) ($(command -v railway))"
    else
      echo "[WARN] Railway CLI download failed (check network/proxy allowlist)" >&2
      if [ "${MODE}" = "bootstrap" ] || [ "${STRICT}" -eq 1 ]; then
        exit 1
      fi
    fi
  fi
fi

# 4. Automated Repository & Gateway Smoke Validation during setup
if [ "${SKIP_VALIDATE}" -eq 0 ] && { [ "${MODE}" = "setup" ] || [ "${MODE}" = "check" ]; }; then
  echo "------------------------------------------------------------------------"
  echo "[VALIDATE] Running repository & gateway validation suite..."
  (cd "${REPO_ROOT}" && bash "${SCRIPT_DIR}/validate.sh")
fi

echo "------------------------------------------------------------------------"

# 5. Read-Only Environment & Personal Vault Inspection
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
  elif [[ "${val}" == CODEX_NET_SECRET* ]] && [[ "${var_name}" =~ ^(SCL_RAILWAY_API_TOKEN|SCL_CF_API_TOKEN|SCL_MCP_BASE_SECRET|SCL_CLAUDE_CODE_OAUTH_TOKEN)$ ]]; then
    missing_admin+=("  - ${var_name}: Set as 'Network secret' placeholder; move to 'Environment variable' in Personal Vault")
  fi
}

check_var "SCL_CF_DOMAIN"               "shared" "Shared Cloud Environment -> Environment variables (e.g. mytunnels.fyi)"
check_var "SCL_CF_ACCESS_CLIENT_ID"     "shared" "Shared Cloud Environment -> Environment variables"
check_var "SCL_CF_ACCESS_CLIENT_SECRET" "shared" "Shared Cloud Environment -> Network secrets (*.mytunnels.fyi) or Environment variables"

check_var "SCL_MCP_BASE_SECRET"         "admin"  "Personal Vault -> Environment variables (openssl rand -hex 32)"
check_var "SCL_CLAUDE_CODE_OAUTH_TOKEN" "admin"  "Personal Vault -> Environment variables (claude setup-token)"
check_var "SCL_CF_ACCOUNT_ID"           "admin"  "Personal Vault -> Environment variables"
check_var "SCL_CF_ZONE_ID"              "admin"  "Personal Vault -> Environment variables"
check_var "SCL_CF_API_TOKEN"            "admin"  "Personal Vault -> Environment variables (Cloudflare API Token)"
check_var "SCL_RAILWAY_API_TOKEN"       "admin"  "Personal Vault -> Environment variables (Railway API Token)"

if [ ${#missing_shared[@]} -eq 0 ]; then
  echo "[OK] Shared Operator Environment Variables: READY"
else
  echo "[MISSING] Shared Cloud Environment Settings:"
  printf '%s\n' "${missing_shared[@]}"
fi

echo "------------------------------------------------------------------------"

if [ ${#missing_admin[@]} -eq 0 ]; then
  echo "[OK] Admin Bootstrap Personal Vault Variables: READY"
else
  echo "[MISSING/MISCONFIGURED] Admin Personal Vault Settings:"
  printf '%s\n' "${missing_admin[@]}"
fi
echo "========================================================================"

# 6. Mode-specific enforcement
if [ "${MODE}" = "setup" ] || [ "${MODE}" = "check" ]; then
  if [ "${STRICT}" -eq 1 ] && { [ ${#missing_shared[@]} -gt 0 ] || [ ${#missing_admin[@]} -gt 0 ]; }; then
    exit 1
  fi
  echo "Setup complete. Worktree is clean ($(git -C "${REPO_ROOT}" status --porcelain | wc -l | tr -d ' ') modified files)."
  exit 0
fi

if [ "${MODE}" = "operate" ]; then
  if [ ${#missing_shared[@]} -gt 0 ]; then
    echo "ERROR: Shared Cloud Environment variables are missing." >&2
    exit 1
  fi
  if [ -z "${SCL_MCP_BEARER_TOKEN:-}" ] && [ -z "${SCL_MCP_BASE_SECRET:-}" ]; then
    echo "ERROR: Operator requires SCL_MCP_BEARER_TOKEN or SCL_MCP_BASE_SECRET." >&2
    exit 1
  fi
  echo "Operator pre-flight passed."
  exit 0
fi

if [ "${MODE}" = "bootstrap" ]; then
  if [ ${#missing_shared[@]} -gt 0 ] || [ ${#missing_admin[@]} -gt 0 ]; then
    echo "ERROR: Cannot bootstrap until all shared and admin variables are set." >&2
    exit 1
  fi

  railway whoami
fi
