#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="${WORKSPACE_DIR:-/workspace}"

mkdir -p \
  "${WORKSPACE}/projects" \
  "${WORKSPACE}/shared" \
  "${WORKSPACE}/secrets" \
  "${WORKSPACE}/logs" \
  "${WORKSPACE}/.claude"

ln -sfn "${WORKSPACE}/.claude" /root/.claude

if [ ! -f "${WORKSPACE}/.claude.json" ]; then
cat << 'EOF' > "${WORKSPACE}/.claude.json"
{
"hasCompletedOnboarding": true,
"theme": "dark",
"bypassPermissionsModeAccepted": true
}
EOF
fi
ln -sfn "${WORKSPACE}/.claude.json" /root/.claude.json

cat << 'EOF' > /root/.tmux.conf
set -g history-limit 50000
set -g mouse on
set -g status off
EOF

if ! tmux has-session -t claude-work 2>/dev/null; then
tmux new-session -d -s claude-work -c "${WORKSPACE}/projects"
fi

supergateway \
  --stdio "tmux-mcp" \
  --outputTransport streamableHttp \
  --stateful \
  --port 8001 \
  --streamableHttpPath /mcp \
  > "${WORKSPACE}/logs/tmux-mcp.log" 2>&1 &

supergateway \
  --stdio "mcp-server-filesystem ${WORKSPACE}" \
  --outputTransport streamableHttp \
  --stateful \
  --port 8002 \
  --streamableHttpPath /mcp \
  > "${WORKSPACE}/logs/files-mcp.log" 2>&1 &

exec node /opt/worker/gateway.mjs
