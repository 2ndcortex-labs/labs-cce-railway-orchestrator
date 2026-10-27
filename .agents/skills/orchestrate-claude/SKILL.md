---
name: orchestrate-claude
description: Interactive entry-point router for CCE Railway Claude Code sessions. Immediately prompts the user to choose between Operating an existing project, Bootstrapping a new isolated project, or running Fleet Discovery, then routes to the selected workflow.
---

# Skill: Orchestrate Claude (`orchestrate-claude`)

## Immediate Action on Invocation

When this skill is invoked (or when a session starts without an explicit `<project-slug>` command), **immediately ask the user which of the 3 operational workflows they want to run**:

> **How would you like to proceed in this session?**
> 1. **Operate an Existing Project (`operate <project-slug>`)** — Attach to an existing Railway worker (`rw-<project-slug>`) and run Claude Code, shell, or file tasks over its Cloudflare Tunnel.
> 2. **Bootstrap a New Isolated Project (`bootstrap <project-slug>`)** — Provision a new Cloudflare Tunnel (`rw-<project-slug>`), DNS CNAME, and standalone Railway project with a persistent `/workspace` volume.
> 3. **Fleet Discovery (`list`)** — Query Cloudflare and Railway to list all active `rw-<project-slug>` workers and check their `/health` status before choosing one.
>
> *Reply with **1**, **2**, or **3** (and the `<project-slug>` if choosing 1 or 2).*

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

1. If the user selected **Option 2** without naming `<project-slug>`, ask: *"What `<project-slug>` (lowercase letters, numbers, and hyphens) should we use for the new Railway project?"*
2. Once `<project-slug>` is provided, read and follow **`.agents/skills/bootstrap-railway-project/SKILL.md`**:
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

2. For each discovered `<project-slug>`, optionally ping `https://<project-slug>.${CF_DOMAIN}/health` with `CF-Access-Client-Id` and `CF-Access-Client-Secret` to show whether it is online.
3. Present the table of discovered `<project-slug>` workers to the user and ask whether they want to **Operate (1)** one of them or **Bootstrap (2)** a new `<project-slug>`.
