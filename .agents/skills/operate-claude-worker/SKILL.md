---
name: operate-claude-worker
description: Connects to an existing Railway project worker by project-slug to share secrets, upload/read files via Filesystem MCP, and operate Claude Code (claude, /exit, claude --resume) via tmux-mcp over HTTPS (Port 443).
---

# Operate Claude Worker Skill

Requires `<project-slug>` and `<domain>`.

## 1. Authenticate & Connect

- `MCP_TOKEN=$(./scripts/derive-token.sh "<project-slug>")`

- Configure remote Streamable HTTP MCP endpoints with header `Authorization: Bearer ${MCP_TOKEN}`:

  - `tmux-mcp`: `<domain>/tmux`

  - `files-mcp`: `<domain>/files`

## 2. Sharing Secrets

- Inject environment variables via Railway CLI:

  `railway variables --set "KEY=VALUE" --service "claude-worker"`

- Or write `.env` files to `/workspace/projects/<subproject>/.env` via `files-mcp` (`write_file`).

## 3. Sharing Files

- Use `files-mcp` (`write_file`, `edit_file`, `read_file`, `list_directory`) inside `/workspace/projects/` or `/workspace/shared/`.

## 4. Operating Claude Code (`claude`, `/exit`, `claude --resume`)

Use `tmux-mcp` targeting the `claude-work` session:

- **Check state:** Call `capture-pane` on `claude-work` before sending input.

- **Start Claude:** Send `claude` (or `claude --dangerously-skip-permissions`) + `Enter` via `send-keys`.

- **Prompt Claude:** Send prompt text + `Enter` via `send-keys`, then poll `capture-pane`.

- **Exit to shell:** Send `/exit` + `Enter` via `send-keys` and verify the bash prompt via `capture-pane`.

- **Resume session:** From bash, send `claude --resume` (or `claude --resume <session-id>`) + `Enter` via `send-keys`.
