---
name: bootstrap-railway-project
description: Provisions a new Railway project, Cloudflare Tunnel (<project-slug>.<CF_DOMAIN>), and persistent Claude Code worker container (with Volume at /workspace/nethub/nexus, ttyd, tmux-mcp, Filesystem MCP, and Remote Control support).
---

# Bootstrap Railway Project Skill

Require a `<project-slug>` from the operator before running.

## Execution Steps

1. **Verify Environment, Derive MCP Token & Provision Cloudflare Tunnel**
   - `./scripts/cce-init.sh`
   - `MCP_TOKEN=$(./scripts/derive-token.sh "<project-slug>")`
   - `CF_TUNNEL_TOKEN=$(./scripts/provision-cf-tunnel.sh "<project-slug>")`
   - `DOMAIN="https://<project-slug>.${CF_DOMAIN}"`

2. **Create Railway Project, Service, and Persistent Volume**
   - `mkdir -p "/tmp/rw-<project-slug>" && cp -r templates/railway-worker/* "/tmp/rw-<project-slug>/"`
   - `cd "/tmp/rw-<project-slug>"`
   - `railway init --name "<project-slug>"`
   - `railway add --service "claude-worker"`
   - `railway service "claude-worker"`
   - `railway volume add --mount-path /workspace`

3. **Inject Secrets into the Railway Service (Zero Public Railway Ports)**
   - `railway variables --set "CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN}"`
   - `railway variables --set "MCP_BEARER_TOKEN=${MCP_TOKEN}"`
   - `railway variables --set "CF_TUNNEL_TOKEN=${CF_TUNNEL_TOKEN}"`
   - `railway variables --set "WORKSPACE_DIR=/workspace"`

4. **Deploy Worker Container (Outbound Cloudflare Tunnel Only)**
   - `railway up --detach`
   - Do NOT run `railway domain` — the container remains dark on Railway's edge and connects outbound via `cloudflared`.

5. **Register Remote MCP Servers in CCE & Verify Health**
   - Poll `${DOMAIN}/health` with headers `CF-Access-Client-Id: ${CF_ACCESS_CLIENT_ID}` and `CF-Access-Client-Secret: ${CF_ACCESS_CLIENT_SECRET}` until HTTP 200 is returned.
   - Register remote Streamable HTTP MCP servers with headers `CF-Access-Client-Id`, `CF-Access-Client-Secret`, and `Authorization: Bearer ${MCP_TOKEN}`:
     - `tmux-mcp`: `${DOMAIN}/tmux`
     - `files-mcp`: `${DOMAIN}/files`
   - Web terminal (`ttyd`) is live at `${DOMAIN}/terminal`.
