---
name: bootstrap-railway-project
description: Provision a brand-new isolated Railway project (rw-<project-slug>), persistent /workspace volume, and Cloudflare Tunnel, deploy templates/railway-worker, and attach.
---

# Skill: Bootstrap Isolated Railway Project (`<project-slug>`)

## 0. Directive 2 Pre-Note: Empty GitHub Repository URL for `nexus/`
Per Directive 2, the Claude Code session launched inside `/workspace/corhub/nexus` on first run will ask for the project's empty GitHub repository remote URL to initialize `nexus/`.
- If the user already provided the empty GitHub repository URL, export `NEXUS_GIT_REMOTE="<url>"` so it is persisted in `/tmp/cce-session-<project-slug>.env` for Step 4.
- If the user has not provided it yet, do **not** block provisioning—start provisioning immediately and inform the user: *"While Railway builds `rw-<project-slug>` (60–120s), please have an empty GitHub repository URL ready for `nexus/` first-run initialization."*

## 1. Verify Admin Pre-Flight & Railway Auth
Ensure the CLI path is active and verify all admin secrets:

    export PATH="/workspace/.onboarding/bin:${HOME}/.local/bin:${PATH}"
    ./scripts/cce-init.sh --mode bootstrap --skip-validate

## 2. Derive Token & Provision Cloudflare Tunnel + DNS
Set `PROJECT_SLUG` (lowercase alphanumeric + hyphens) and provision its tunnel and DNS CNAME (`<project-slug>.${SCL_CF_DOMAIN}`):

    export PROJECT_SLUG="<project-slug>"
    export WORKER_TOKEN="$(./scripts/derive-token.sh "${PROJECT_SLUG}")"
    export CF_TUNNEL_TOKEN="$(./scripts/provision-cf-tunnel.sh "${PROJECT_SLUG}")"

## 3. Create Standalone Railway Project (`rw-<project-slug>`) From Temp Staging
Always stage `templates/railway-worker/` in a temporary directory so the orchestrator git worktree stays clean:

    STAGE_DIR="$(mktemp -d)"
    cp -R templates/railway-worker/. "${STAGE_DIR}/"
    pushd "${STAGE_DIR}" >/dev/null

    export RAILWAY_API_TOKEN="${SCL_RAILWAY_API_TOKEN}"
    railway init --name "rw-${PROJECT_SLUG}"
    railway add --service "worker"
    railway service "worker"
    railway volume add --mount-path /workspace

    railway variables --set \
      "PROJECT_SLUG=${PROJECT_SLUG}" \
      "MCP_BEARER_TOKEN=${WORKER_TOKEN}" \
      "CF_TUNNEL_TOKEN=${CF_TUNNEL_TOKEN}" \
      "CLAUDE_CODE_OAUTH_TOKEN=${SCL_CLAUDE_CODE_OAUTH_TOKEN}"

    railway up --detach
    popd >/dev/null
    rm -rf "${STAGE_DIR}"

*Security Rule:* Never run `railway domain`. All ingress flows exclusively through the Cloudflare Tunnel.

## 4. Poll `/health`, Save Session Context, & Transition to Operate Skill
Wait for Railway to finish building and starting the worker container (typically 60-120 seconds):

    CLEAN_DOMAIN=$(printf '%s' "${SCL_CF_DOMAIN}" | tr -d '\r\n ' | sed -E 's/^\*\.//')
    WORKER_HOST="${PROJECT_SLUG}.${CLEAN_DOMAIN}"
    WORKER_URL="https://${WORKER_HOST}"
    for i in $(seq 1 30); do
      if curl -fsSL "${WORKER_URL}/health" \
        -H "CF-Access-Client-Id: ${SCL_CF_ACCESS_CLIENT_ID}" \
        -H "CF-Access-Client-Secret: ${SCL_CF_ACCESS_CLIENT_SECRET}" 2>/dev/null | grep -q '"ok":true'; then
        echo "Worker ${PROJECT_SLUG} is ONLINE at ${WORKER_URL}"
        break
      fi
      echo "Waiting for ${WORKER_URL}/health (attempt ${i}/30)..."
      sleep 5
    done

    cat <<EOF2 > "/tmp/cce-session-${PROJECT_SLUG}.env"
    export PROJECT_SLUG="${PROJECT_SLUG}"
    export WORKER_HOST="${WORKER_HOST}"
    export WORKER_URL="${WORKER_URL}"
    export WORKER_TOKEN="${WORKER_TOKEN}"
    export NEXUS_GIT_REMOTE="${NEXUS_GIT_REMOTE:-}"
    EOF2

Once `/health` returns `{"ok":true}`, immediately follow `.agents/skills/operate-claude-worker/SKILL.md` for `<project-slug>`.
