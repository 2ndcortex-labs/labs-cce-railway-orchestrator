---
name: bootstrap-railway-project
description: Provision a brand-new isolated Railway project (rw-<project-slug>), persistent /workspace volume, and Cloudflare Tunnel, deploy templates/railway-worker, and attach.
---

# Skill: Bootstrap Isolated Railway Project (`<project-slug>`)

## 1. Verify Admin Pre-Flight & Railway Auth
Ensure the CLI path is active and verify all admin secrets:

    export PATH="/workspace/.onboarding/bin:${HOME}/.local/bin:${PATH}"
    ./scripts/cce-init.sh --mode bootstrap --skip-validate

## 2. Derive Token & Provision Cloudflare Tunnel + DNS
Set `PROJECT_SLUG` (lowercase alphanumeric + hyphens) and provision its tunnel and DNS CNAME (`<project-slug>.${CF_DOMAIN}`):

    export PROJECT_SLUG="<project-slug>"
    export WORKER_TOKEN="$(./scripts/derive-token.sh "${PROJECT_SLUG}")"
    export CF_TUNNEL_TOKEN="$(./scripts/provision-cf-tunnel.sh "${PROJECT_SLUG}")"

## 3. Create Standalone Railway Project (`rw-<project-slug>`) From Temp Staging
Always stage `templates/railway-worker/` in a temporary directory so the orchestrator git worktree stays clean:

    STAGE_DIR="$(mktemp -d)"
    cp -R templates/railway-worker/. "${STAGE_DIR}/"
    pushd "${STAGE_DIR}" >/dev/null

    railway init --name "rw-${PROJECT_SLUG}"
    railway add --service "worker"
    railway service "worker"
    railway volume add --mount-path /workspace

    railway variables --set \
      "PROJECT_SLUG=${PROJECT_SLUG}" \
      "MCP_BEARER_TOKEN=${WORKER_TOKEN}" \
      "CF_TUNNEL_TOKEN=${CF_TUNNEL_TOKEN}" \
      "CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN}"

    railway up --detach
    popd >/dev/null
    rm -rf "${STAGE_DIR}"

*Security Rule:* Never run `railway domain`. All ingress flows exclusively through the Cloudflare Tunnel.

## 4. Poll `/health` & Transition to Operate Skill
Wait for Railway to finish building and starting the worker container (typically 60-120 seconds):

    CLEAN_DOMAIN=$(printf '%s' "${CF_DOMAIN}" | tr -d '\r\n ' | sed -E 's/^\*\.//')
    WORKER_URL="https://${PROJECT_SLUG}.${CLEAN_DOMAIN}"
    for i in $(seq 1 30); do
      if curl -fsSL "${WORKER_URL}/health" \
        -H "CF-Access-Client-Id: ${CF_ACCESS_CLIENT_ID}" \
        -H "CF-Access-Client-Secret: ${CF_ACCESS_CLIENT_SECRET}" 2>/dev/null | grep -q '"ok":true'; then
        echo "Worker ${PROJECT_SLUG} is ONLINE at ${WORKER_URL}"
        break
      fi
      echo "Waiting for ${WORKER_URL}/health (attempt ${i}/30)..."
      sleep 5
    done

Once `/health` returns `{"ok":true}`, immediately follow `.agents/skills/operate-claude-worker/SKILL.md` for `<project-slug>`.
