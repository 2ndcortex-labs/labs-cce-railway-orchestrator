---
name: operate-claude-worker
description: Attach to and operate an existing isolated Railway Claude Code worker project (<project-slug>) over its Cloudflare Tunnel MCP endpoints (/tmux, /files, /terminal).
---

# Skill: Operate Claude Worker (`<project-slug>`)

## 1. Bind Chat Session to `<project-slug>`
Verify operator credentials and save the session parameters to `/tmp/cce-session-<project-slug>.env`:

    export PATH="/workspace/.onboarding/bin:${HOME}/.local/bin:${PATH}"
    export PROJECT_SLUG="<project-slug>"
    ./scripts/cce-init.sh --mode operate --skip-cli --skip-validate

    CLEAN_DOMAIN=$(printf '%s' "${CF_DOMAIN}" | tr -d '\r\n ' | sed -E 's/^\*\.//')
    export WORKER_HOST="${PROJECT_SLUG}.${CLEAN_DOMAIN}"
    export WORKER_URL="https://${WORKER_HOST}"

    if [ -n "${MCP_BASE_SECRET:-}" ]; then
      export WORKER_TOKEN="$(./scripts/derive-token.sh "${PROJECT_SLUG}")"
    else
      export WORKER_TOKEN="${MCP_BEARER_TOKEN}"
    fi

    cat <<EOF2 > "/tmp/cce-session-${PROJECT_SLUG}.env"
    export PROJECT_SLUG="${PROJECT_SLUG}"
    export WORKER_HOST="${WORKER_HOST}"
    export WORKER_URL="${WORKER_URL}"
    export WORKER_TOKEN="${WORKER_TOKEN}"
    EOF2

## 2. Verify Worker Health
Check that the worker container and Cloudflare Tunnel are online:

    source "/tmp/cce-session-${PROJECT_SLUG}.env"
    curl -fsSL "${WORKER_URL}/health" \
      -H "CF-Access-Client-Id: ${CF_ACCESS_CLIENT_ID}" \
      -H "CF-Access-Client-Secret: ${CF_ACCESS_CLIENT_SECRET}"

If `/health` is unreachable (`530` / `404`), check whether `rw-${PROJECT_SLUG}` exists in Railway (`railway list`) and ask the user if they want to bootstrap `<project-slug>` using `.agents/skills/bootstrap-railway-project/SKILL.md`.

## 3. Directive 2 Instance Layout & Launching Claude Code
Every worker volume (`/workspace`) is structured according to Directive 2:
- `/workspace/CLAUDE.md` — Root beacon (`# Root beacon`) that stops Claude if launched in `/workspace` directly.
- `/workspace/corhub/` — Full clone of `2ndcortex-labs/corhub`.
- `/workspace/corhub/nexus/` — The project folder where `claude-work` tmux starts and where Claude Code MUST be launched.
- `/workspace/.corhub-instance-report.txt` — Verification report generated on first container boot.

**First-Attach Check & Launch Command:**
1. Inspect `/workspace/.corhub-instance-report.txt` via `/files` MCP to confirm all 5 Directive 2 checks passed.
2. Always launch Claude Code inside the `claude-work` tmux session from `/workspace/corhub/nexus` using the exact command:

       cd /workspace/corhub/nexus && claude

3. **First-Run Project Initialization & Folder Permissions:**
   - The session launched from `/workspace/corhub/nexus` will ask for the project's git remote URL on first run; the human should have an empty GitHub repository ready for it.
   - Claude Code will ask permission the first time the session reaches a folder outside `nexus/`, which the operator/human approves.

## 4. Execute Remote MCP Tools (`/tmux` & `/files`)
Use `./scripts/mcp-call.sh` to list or call MCP tools on the worker over SSE/JSON-RPC:

- **List available tools on `/tmux` or `/files`:**

      ./scripts/mcp-call.sh "${PROJECT_SLUG}" tmux tools/list '{}'
      ./scripts/mcp-call.sh "${PROJECT_SLUG}" files tools/list '{}'

- **Read the Directive 2 verification report via `/files`:**

      ./scripts/mcp-call.sh "${PROJECT_SLUG}" files tools/call '{"name":"read_file","arguments":{"path":"/workspace/.corhub-instance-report.txt"}}'

- **Call a tool on `/tmux` (e.g., launch Claude or run a command in `claude-work`):**

      ./scripts/mcp-call.sh "${PROJECT_SLUG}" tmux tools/call '{"name":"execute-command","arguments":{"sessionId":"claude-work","command":"cd /workspace/corhub/nexus && claude"}}'

## 5. Human Web Terminal (`/terminal`)
Share `https://${WORKER_HOST}/terminal` when the user wants to view or type in the live `claude-work` tmux session in their browser.
