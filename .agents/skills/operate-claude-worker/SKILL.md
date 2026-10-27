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

    cat <<EOF > "/tmp/cce-session-${PROJECT_SLUG}.env"
    export PROJECT_SLUG="${PROJECT_SLUG}"
    export WORKER_HOST="${WORKER_HOST}"
    export WORKER_URL="${WORKER_URL}"
    export WORKER_TOKEN="${WORKER_TOKEN}"
    EOF

## 2. Verify Worker Health
Check that the worker container and Cloudflare Tunnel are online:

    source "/tmp/cce-session-${PROJECT_SLUG}.env"
    curl -fsSL "${WORKER_URL}/health" \
      -H "CF-Access-Client-Id: ${CF_ACCESS_CLIENT_ID}" \
      -H "CF-Access-Client-Secret: ${CF_ACCESS_CLIENT_SECRET}"

If `/health` is unreachable (`530` / `404`), check whether `rw-${PROJECT_SLUG}` exists in Railway (`railway list`) and ask the user if they want to bootstrap `<project-slug>` using `.agents/skills/bootstrap-railway-project/SKILL.md`.

## 3. Execute Remote MCP Tools (`/tmux` & `/files`)
Use `./scripts/mcp-call.sh` to list or call MCP tools on the worker over SSE/JSON-RPC:

- **List available tools on `/tmux` or `/files`:**

      ./scripts/mcp-call.sh "${PROJECT_SLUG}" tmux tools/list '{}'
      ./scripts/mcp-call.sh "${PROJECT_SLUG}" files tools/list '{}'

- **Call a tool on `/tmux` (e.g., execute command or read pane output in `claude-work`):**

      ./scripts/mcp-call.sh "${PROJECT_SLUG}" tmux tools/call '{"name":"execute-command","arguments":{"sessionId":"claude-work","command":"git status"}}'

- **Call a tool on `/files` (e.g., list or read `/workspace` files):**

      ./scripts/mcp-call.sh "${PROJECT_SLUG}" files tools/call '{"name":"list_directory","arguments":{"path":"/workspace"}}'

## 4. Human Web Terminal (`/terminal`)
Share `https://${WORKER_HOST}/terminal` when the user wants to view or type in the live `claude-work` tmux session in their browser.
