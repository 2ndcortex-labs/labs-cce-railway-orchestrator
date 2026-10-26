---
name: operate-claude-worker
description: Connects to an existing Railway worker over Cloudflare Tunnel (<project-slug>.<CF_DOMAIN>) to share secrets, manage files in /workspace/nethub/nexus via Filesystem MCP, and operate Claude Code (including --rc Remote Control, /exit, claude --resume, and ttyd) via tmux-mcp.
---

# Operate Claude Worker Skill

Requires `<project-slug>` (which resolves to `DOMAIN="https://<project-slug>.${CF_DOMAIN}"`).

## 1. Authenticate & Connect (Dual-Wall Security)
- `MCP_TOKEN=$(./scripts/derive-token.sh "<project-slug>")`
- Configure remote Streamable HTTP MCP endpoints with all 3 headers (`CF-Access-Client-Id: ${CF_ACCESS_CLIENT_ID}`, `CF-Access-Client-Secret: ${CF_ACCESS_CLIENT_SECRET}`, and `Authorization: Bearer ${MCP_TOKEN}`):
  - `tmux-mcp`: `https://<project-slug>.${CF_DOMAIN}/tmux`
  - `files-mcp`: `https://<project-slug>.${CF_DOMAIN}/files`
- **Human Web Terminal (`ttyd`):** Open `https://<project-slug>.${CF_DOMAIN}/terminal` in a browser (authenticated via Cloudflare Zero Trust) to view and type into `claude-work` alongside Codex.

## 2. Sharing Secrets
- Inject environment variables via Railway CLI:
  `railway variables --set "KEY=VALUE" --service "claude-worker"`
- Or write `.env` files to `/workspace/nethub/nexus/.env` (or `/workspace/secrets/`) via `files-mcp` (`write_file`).

## 3. Sharing Files
- Use `files-mcp` (`write_file`, `edit_file`, `read_file`, `list_directory`) targeting `/workspace/nethub/nexus/` (primary working directory), `/workspace/projects/`, or `/workspace/shared/`.

## 4. Operating Claude Code + Remote Control (`--rc`) in `claude-work`
Use `tmux-mcp` targeting the `claude-work` session (rooted in `/workspace/nethub/nexus`):
- **Check state:** Call `capture-pane` on `claude-work` before sending input.
- **Start Claude with Remote Control (Interactive Mode):**
  Send `claude --rc "<project-slug>"` (or `claude --rc "<project-slug>" --dangerously-skip-permissions`) + `Enter` via `send-keys`.
  *(Note: Never use `claude remote-control` server mode, as it disables the local interactive TUI inside tmux. If Remote Control prompts for full-scope claude.ai OAuth on first run, run `unset CLAUDE_CODE_OAUTH_TOKEN && claude auth login` once inside `claude-work`; credentials persist in `/workspace/.claude`).*
- **Prompt Claude:** Send prompt text + `Enter` via `send-keys`, then poll `capture-pane`.
- **Exit to shell:** Send `/exit` + `Enter` via `send-keys` and verify the bash prompt via `capture-pane`.
- **Resume session with Remote Control:** From bash in `/workspace/nethub/nexus`, send `claude --resume --rc` + `Enter` via `send-keys`.
