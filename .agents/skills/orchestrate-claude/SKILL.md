---
name: orchestrate-claude
description: Interactive entry-point router for CCE Railway Claude Code sessions. Immediately prompts the user to choose between Operating an existing project, Bootstrapping a new isolated project, or running Fleet Discovery, then routes to the selected workflow.
---

# Skill: Orchestrate Claude (`orchestrate-claude`)

## Immediate Action on Invocation

When this skill is invoked (or when a session starts without an explicit `<project-slug>` command), **immediately ask the user which of the 3 operational workflows they want to run**:

> **How would you like to proceed in this session?**
> 1. **Operate an Existing Project (`operate <project-slug>`)** — Attach to an existing Railway worker (`rw-<project-slug>`) and run Claude Code, shell, or file tasks over its Cloudflare Tunnel.
> 2. **Bootstrap a New Isolated Project (`bootstrap <project-slug>`)** — Provision a new Cloudflare Tunnel (`rw-<project-slug>`), DNS CNAME, and standalone Railway project with a persistent `/workspace` volume. *(Have an empty GitHub repository URL ready for `nexus/` first-run initialization.)*
> 3. **Fleet Discovery (`list`)** — Query Cloudflare and Railway to list all active `rw-<project-slug>` workers and check their `/health` status before choosing one.
>
> *Reply with **1**, **2**, or **3** (plus `<project-slug>`, and the empty GitHub repository URL if choosing **2**).*

*(If the user already provided their choice or `<project-slug>` in the same message that triggered this skill, skip the prompt and proceed directly to the matching option below.)*

---

## Pre-Check (Run Before Executing Options 1, 2, or 3)

Ensure the Railway CLI path is loaded in the current shell without running full validation:

    export PATH="/workspace/.onboarding/bin:${HOME}/.local/bin:${PATH}"
    command -v railway >/dev/null 2>&1 || ./scripts/cce-init.sh --skip-validate

---

## Option 1: Operate an Existing Project (`operate <project-slug>`)

1. If the user selected **Option 1** without naming `<project-slug>`, ask: *"Which `<project-slug>` would you like to attach to?"* (or run **Option 3: Fleet Discovery** first so they can pick from active projects).
2. Once `<project-slug>` is known, read and follow **`.agents/skills/operate-claude-worker/SKILL.md`**:
   - Run `./scripts/cce-init.sh --mode operate --skip-cli --skip-validate`.
   - Derive the project token via `./scripts/derive-token.sh <project-slug>` and save session state to `/tmp/cce-session-<project-slug>.env`.
   - Verify `https://<project-slug>.${CF_DOMAIN}/health`.
   - Execute all tasks remotely via `./scripts/mcp-call.sh <project-slug> tmux ...` and `./scripts/mcp-call.sh <project-slug> files ...`.

---

## Option 2: Bootstrap a New Isolated Project (`bootstrap <project-slug>`)

1. If the user selected **Option 2** without naming `<project-slug>`, ask:
   *"What `<project-slug>` (lowercase letters, numbers, and hyphens) should we use for the new Railway project, and what is the empty GitHub repository URL for initializing `nexus/` on first run?"*
2. If the user provided `<project-slug>` without the empty GitHub repository URL yet, remind them to create or share the empty GitHub repository URL while the Railway worker builds, then proceed immediately with **`.agents/skills/bootstrap-railway-project/SKILL.md`**:
   - Run `./scripts/cce-init.sh --mode bootstrap --skip-validate`.
   - Derive the bearer token (`./scripts/derive-token.sh <project-slug>`) and provision the Cloudflare Tunnel + DNS (`./scripts/provision-cf-tunnel.sh <project-slug>`).
   - Stage `templates/railway-worker/` in `mktemp -d`, create standalone Railway project `rw-<project-slug>`, attach `/workspace` volume, set variables, and deploy with `railway up --detach`.
   - Poll `https://<project-slug>.${CF_DOMAIN}/health` until `{"ok":true}` and automatically transition into **Option 1 (`operate-claude-worker`)**.

---

## Option 3: Fleet Discovery (`list`)

1. Query active `rw-*` Cloudflare Tunnels and Railway projects:

       CLEAN_TOKEN=$(printf '%s' "${CF_API_TOKEN:-}" | tr -d '\r\n' | sed -E 's/^[[:space:]"'"'"']+//; s/[[:space:]"'"'"']+$//; s/^Bearer[[:space:]]+//I')
       if [ -n "${CLEAN_TOKEN}" ] && [ -n "${CF_ACCOUNT_ID:-}" ]; then
         echo "=== Active Cloudflare Worker Tunnels (rw-*) ==="
         curl -fsSL "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/cfd_tunnel?is_deleted=false" \
           -H "Authorization: Bearer ${CLEAN_TOKEN}" \
           | jq -r '.result[] | select(.name | startswith("rw-")) | "\(.name | sub("^rw-"; ""))\tTunnel: \(.status)\tID: \(.id)"'
       fi
       if [ -n "${RAILWAY_API_TOKEN:-}" ]; then
         echo "=== Railway Projects ==="
         RAILWAY_API_TOKEN="${RAILWAY_API_TOKEN}" railway list || true
       fi

2. For each discovered `<project-slug>`, optionally ping `https://<project-slug>.${CF_DOMAIN}/health` with `CF-Access-Client-Id` and `CF-Access-Client-Secret` to show whether it is online. 3. Present the table of discovered `<project-slug>` workers to the user and ask whether they want to **Operate (1)** one of them or **Bootstrap (2)** a new `<project-slug>`. EOF  cat << 'EOF' > .agents/skills/bootstrap-railway-project/SKILL.md --- name: bootstrap-railway-project description: Provision a brand-new isolated Railway project (rw-<project-slug>), persistent /workspace volume, and Cloudflare Tunnel, deploy templates/railway-worker, and attach. ---  # Skill: Bootstrap Isolated Railway Project (`<project-slug>`)  ## 0. Directive 2 Pre-Note: Empty GitHub Repository URL for `nexus/` Per Directive 2, the Claude Code session launched inside `/workspace/corhub/nexus` on first run will ask for the project's empty GitHub repository remote URL to initialize `nexus/`. - If the user already provided the empty GitHub repository URL, export `NEXUS_GIT_REMOTE="<url>"` so it is persisted in `/tmp/cce-session-<project-slug>.env` for Step 4. - If the user has not provided it yet, do **not** block provisioning—start provisioning immediately and inform the user: *"While Railway builds `rw-<project-slug>` (60–120s), please have an empty GitHub repository URL ready for `nexus/` first-run initialization."*  ## 1. Verify Admin Pre-Flight & Railway Auth Ensure the CLI path is active and verify all admin secrets:  export PATH="/workspace/.onboarding/bin:${HOME}/.local/bin:${PATH}" ./scripts/cce-init.sh --mode bootstrap --skip-validate  ## 2. Derive Token & Provision Cloudflare Tunnel + DNS Set `PROJECT_SLUG` (lowercase alphanumeric + hyphens) and provision its tunnel and DNS CNAME (`<project-slug>.${CF_DOMAIN}`):

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

## 4. Poll `/health`, Save Session Context, & Transition to Operate Skill
Wait for Railway to finish building and starting the worker container (typically 60-120 seconds):

    CLEAN_DOMAIN=$(printf '%s' "${CF_DOMAIN}" | tr -d '\r\n ' | sed -E 's/^\*\.//')
    WORKER_HOST="${PROJECT_SLUG}.${CLEAN_DOMAIN}"
    WORKER_URL="https://${WORKER_HOST}"
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

    cat <<EOF2 > "/tmp/cce-session-${PROJECT_SLUG}.env"
    export PROJECT_SLUG="${PROJECT_SLUG}"
    export WORKER_HOST="${WORKER_HOST}"
    export WORKER_URL="${WORKER_URL}"
    export WORKER_TOKEN="${WORKER_TOKEN}"
    export NEXUS_GIT_REMOTE="${NEXUS_GIT_REMOTE:-}"
    EOF2

Once `/health` returns `{"ok":true}`, immediately follow `.agents/skills/operate-claude-worker/SKILL.md` for `<project-slug>`.
