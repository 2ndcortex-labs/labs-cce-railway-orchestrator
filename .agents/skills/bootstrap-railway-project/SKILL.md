---
name: bootstrap-railway-project
description: Provisions a new Railway project and persistent Claude Code worker container (with Volume, OAuth token, derived MCP Bearer token, tmux-mcp, and Filesystem MCP) given an operator-provided project-slug.
---

# Bootstrap Railway Project Skill
Require a <project-slug> from the operator before running.
## Execution Steps
1. Verify Environment & Derive Project MCP Token
   * : "${RAILWAY_API_TOKEN:?RAILWAY_API_TOKEN must be set in CCE secrets}"
   * MCP_TOKEN=$(./scripts/derive-token.sh "<project-slug>")
2. Create Railway Project, Service, and Persistent Volume
   * mkdir -p "/tmp/rw-<project-slug>" && cp -r templates/railway-worker/* "/tmp/rw-<project-slug>/"
   * cd "/tmp/rw-<project-slug>"
   * railway init --name "<project-slug>"
   * railway add --service "claude-worker"
   * railway service "claude-worker"
   * railway volume add --mount-path /workspace
3. Inject Secrets into the Railway Service
   * railway variables --set "CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN}"
   * railway variables --set "MCP_BEARER_TOKEN=${MCP_TOKEN}"
   * railway variables --set "WORKSPACE_DIR=/workspace"
4. Deploy Worker Container & Generate Public HTTPS Domain
   * railway up --detach
   * DOMAIN=$(railway domain --json | jq -r '.domain // empty')
5. Register Remote MCP Servers in CCE & Verify Health
   * Poll ${DOMAIN}/health until HTTP 200 is returned.
   * Register remote Streamable HTTP MCP servers with header Authorization: Bearer ${MCP_TOKEN}:
      * tmux-mcp: ${DOMAIN}/tmux
      * files-mcp: ${DOMAIN}/files
