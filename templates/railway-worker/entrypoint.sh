#!/usr/bin/env bash
set -euo pipefail

export WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
export TMUX_SESSION="${TMUX_SESSION:-claude-work}"
export CORHUB_REPO_URL="${CORHUB_REPO_URL:-https://github.com/2ndcortex-labs/corhub.git}"

mkdir -p "${WORKSPACE_DIR}"
cd "${WORKSPACE_DIR}"

# Configure git safe directory for persistent Railway volume mounts
git config --global --add safe.directory "${WORKSPACE_DIR}" || true

# Configure GitHub token auth if GH_TOKEN or GITHUB_TOKEN is provided
if [ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]; then
  TOKEN_VAL="${GH_TOKEN:-${GITHUB_TOKEN}}"
  git config --global url."https://x-access-token:${TOKEN_VAL}@github.com/".insteadOf "https://github.com/"
fi

# ---------------------------------------------------------------------------
# 1. Idempotent First-Boot Seeding of /workspace with corhub
# ---------------------------------------------------------------------------
if [ ! -d "${WORKSPACE_DIR}/.claude" ]; then
  echo "[entrypoint] First boot detected on persistent volume. Seeding ${WORKSPACE_DIR} with corhub..."
  TMP_SEED="$(mktemp -d)"
  if git clone --depth 1 "${CORHUB_REPO_URL}" "${TMP_SEED}/corhub" 2>/dev/null; then
    cp -a "${TMP_SEED}/corhub/." "${WORKSPACE_DIR}/"
  elif [ -d "/opt/corhub-seed/.claude" ]; then
    echo "[entrypoint] Live git clone unavailable; seeding from baked-in /opt/corhub-seed..."
    cp -a /opt/corhub-seed/. "${WORKSPACE_DIR}/"
  else
    echo "[entrypoint] WARNING: Could not seed corhub from git or /opt/corhub-seed."
  fi
  rm -rf "${TMP_SEED}"
fi

# Ensure corhub bin utilities and scripts are executable
if [ -d "${WORKSPACE_DIR}/bin" ]; then
  chmod +x "${WORKSPACE_DIR}/bin/"* 2>/dev/null || true
fi

# Seed nexus/ from skeleton/nexus/ on first boot if nexus/roadwork is not initialized yet
if [ -d "${WORKSPACE_DIR}/skeleton/nexus" ] && [ ! -d "${WORKSPACE_DIR}/nexus/roadwork" ]; then
  echo "[entrypoint] Initializing ${WORKSPACE_DIR}/nexus from skeleton/nexus..."
  mkdir -p "${WORKSPACE_DIR}/nexus"
  cp -rn "${WORKSPACE_DIR}/skeleton/nexus/." "${WORKSPACE_DIR}/nexus/" 2>/dev/null || \
    cp -a "${WORKSPACE_DIR}/skeleton/nexus/." "${WORKSPACE_DIR}/nexus/"
fi

# Install unlazy hooks into .claude/settings.json if present
if [ -f "${WORKSPACE_DIR}/.claude/skills/unlazy/scripts/install-hooks.mjs" ]; then
  echo "[entrypoint] Installing unlazy hooks in ${WORKSPACE_DIR}..."
  (cd "${WORKSPACE_DIR}" && node .claude/skills/unlazy/scripts/install-hooks.mjs) || \
    echo "[entrypoint] WARNING: install-hooks.mjs returned non-zero; continuing startup."
fi

# ---------------------------------------------------------------------------
# 2. Ensure Persistent Tmux Session (claude-work) Rooted at /workspace
# ---------------------------------------------------------------------------
if ! tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
  tmux new-session -d -s "${TMUX_SESSION}" -c "${WORKSPACE_DIR}"
fi

# ---------------------------------------------------------------------------
# 3. Start Internal MCP & Web Terminal Services (Loopback Only)
# ---------------------------------------------------------------------------
echo "[entrypoint] Starting Supergateway (tmux-mcp) on 127.0.0.1:8001..."
supergateway \
  --stdio "npx -y tmux-mcp" \
  --port 8001 \
  --baseUrl "http://127.0.0.1:8001/tmux" \
  --ssePath "/tmux/sse" \
  --messagePath "/tmux/message" &

echo "[entrypoint] Starting Supergateway (filesystem-mcp) on 127.0.0.1:8002..."
supergateway \
  --stdio "npx -y @modelcontextprotocol/server-filesystem ${WORKSPACE_DIR}" \
  --port 8002 \
  --baseUrl "http://127.0.0.1:8002/files" \
  --ssePath "/files/sse" \
  --messagePath "/files/message" &

echo "[entrypoint] Starting ttyd web terminal on 127.0.0.1:7681..."
ttyd -i 127.0.0.1 -p 7681 -W -b /terminal tmux attach-session -t "${TMUX_SESSION}" &

# ---------------------------------------------------------------------------
# 4. Start Internal Auth & Routing Gateway on 127.0.0.1:8080
# ---------------------------------------------------------------------------
echo "[entrypoint] Starting gateway.mjs on 127.0.0.1:8080..."
PORT=8080 node /app/gateway.mjs &
GATEWAY_PID=$!

# ---------------------------------------------------------------------------
# 5. Start Outbound Cloudflare Tunnel (if CF_TUNNEL_TOKEN is configured)
# ---------------------------------------------------------------------------
if [ -n "${CF_TUNNEL_TOKEN:-}" ]; then
  echo "[entrypoint] Starting cloudflared tunnel..."
  cloudflared tunnel --no-autoupdate run --token "${CF_TUNNEL_TOKEN}" &
fi

wait "${GATEWAY_PID}"
