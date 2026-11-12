#!/usr/bin/env bash
set -euo pipefail

export WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
export TMUX_SESSION="${TMUX_SESSION:-claude-work}"
export CORHUB_REPO_URL="${CORHUB_REPO_URL:-https://github.com/2ndcortex-labs/corhub}"

mkdir -p "${WORKSPACE_DIR}"

# Configure GitHub token auth if GH_TOKEN or GITHUB_TOKEN is provided
if [ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]; then
  TOKEN_VAL="${GH_TOKEN:-${GITHUB_TOKEN}}"
  git config --global url."https://x-access-token:${TOKEN_VAL}@github.com/".insteadOf "https://github.com/"
fi

# ---------------------------------------------------------------------------
# 1. Directive 2: Idempotent Claude Code Project Instance Setup in <root> (/workspace)
# ---------------------------------------------------------------------------
setup_corhub_instance() {
  local root="${WORKSPACE_DIR}"

  # If already set up on persistent volume, skip installation
  if [ -d "${root}/corhub" ] || [ -e "${root}/CLAUDE.md" ]; then
    echo "[entrypoint] Existing instance detected in ${root} (corhub/ or CLAUDE.md present). Skipping fresh clone."
    return 0
  fi

  echo "[entrypoint] Setting up new Claude Code project instance in ${root}..."

  # Step 2: git clone https://github.com/2ndcortex-labs/corhub <root>/corhub (Default branch, no options)
  git clone "${CORHUB_REPO_URL}" "${root}/corhub"

  # Step 3: Copy <root>/corhub/skeleton/beacon/CLAUDE.md to <root>/CLAUDE.md
  if [ ! -f "${root}/corhub/skeleton/beacon/CLAUDE.md" ]; then
    echo "[entrypoint] ERROR: Missing template ${root}/corhub/skeleton/beacon/CLAUDE.md" >&2
    return 1
  fi
  cp "${root}/corhub/skeleton/beacon/CLAUDE.md" "${root}/CLAUDE.md"

  # Step 4: Verify and record each result
  local commit_hash
  commit_hash="$(git -C "${root}/corhub" rev-parse HEAD)"

  local v_git="FAIL"
  [ -d "${root}/corhub/.git" ] && v_git="PASS"

  local v_beacon="FAIL"
  if [ -f "${root}/CLAUDE.md" ] && [ "$(head -n 1 "${root}/CLAUDE.md" | tr -d '\r')" = "# Root beacon" ]; then
    v_beacon="PASS"
  fi

  local v_nexus="FAIL"
  if [ -d "${root}/corhub/nexus" ]; then
    local entries
    entries="$(ls -A "${root}/corhub/nexus")"
    [ "${entries}" = ".gitkeep" ] && v_nexus="PASS"
  fi

  local v_files="PASS"
  local missing_items=()
  for req in \
    "${root}/corhub/CLAUDE.md" \
    "${root}/corhub/bin/nexus-git" \
    "${root}/corhub/.claude/rules/roadwork-constitution.md" \
    "${root}/corhub/.claude/skills/MANIFEST" \
    "${root}/corhub/.claude/agents" \
    "${root}/corhub/skeleton/nexus"; do
    if [ ! -e "${req}" ]; then
      v_files="FAIL"
      missing_items+=("${req}")
    fi
  done

  local v_no_nexus_git="FAIL"
  [ ! -e "${root}/corhub/.nexus-git" ] && v_no_nexus_git="PASS"

  {
    echo "=== Directive 2 Instance Report ==="
    echo "Root: ${root}"
    echo "Corhub Commit: ${commit_hash}"
    echo "Check 1 (<root>/corhub/.git/ is a directory): ${v_git}"
    echo "Check 2 (<root>/CLAUDE.md exists & first line is '# Root beacon'): ${v_beacon}"
    echo "Check 3 (<root>/corhub/nexus/ contains only .gitkeep): ${v_nexus}"
    echo "Check 4 (Required corhub files/dirs exist): ${v_files} ${missing_items[*]:-}"
    echo "Check 5 (<root>/corhub/.nexus-git/ does not exist): ${v_no_nexus_git}"
    echo ""
    echo "Launch command:"
    echo "cd ${root}/corhub/nexus && claude"
    echo "Note: The session launched from there will ask for the project's git remote URL on first run; the human should have an empty GitHub repository ready for it; and Claude Code will ask permission the first time the session reaches a folder outside nexus/, which the human approves."
  } | tee "${root}/.corhub-instance-report.txt"

  if [ "${v_git}" != "PASS" ] || [ "${v_beacon}" != "PASS" ] || [ "${v_nexus}" != "PASS" ] || [ "${v_files}" != "PASS" ] || [ "${v_no_nexus_git}" != "PASS" ]; then
    echo "[entrypoint] ERROR: Directive 2 verification failed!" >&2
    return 1
  fi
}

setup_corhub_instance

# ---------------------------------------------------------------------------
# 2. Ensure Persistent Tmux Session (claude-work) Rooted at <root>/corhub/nexus
# ---------------------------------------------------------------------------
LAUNCH_DIR="${WORKSPACE_DIR}/corhub/nexus"
[ -d "${LAUNCH_DIR}" ] || LAUNCH_DIR="${WORKSPACE_DIR}"

if ! tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
  tmux new-session -d -s "${TMUX_SESSION}" -c "${LAUNCH_DIR}"
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
