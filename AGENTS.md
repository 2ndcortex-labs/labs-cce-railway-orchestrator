# CCE Railway Orchestrator — Agent Operating Directives

This repository supports two distinct agent execution contexts in Codex Cloud. Identify your current context below and follow ONLY that section:

1. **Context A — Environment Onboarding & Setup Agent:** Active when initializing, building, or validating the Codex Cloud container environment itself (or when the user explicitly requests environment setup/diagnostics).
2. **Context B — Interactive Project Operator (Per-Chat Default):** Active in all normal user chat sessions for provisioning, operating, or inspecting isolated Railway worker projects (`<project-slug>`).

---

## Context A: Environment Onboarding & Automated Setup

**Trigger:** You are the Codex Cloud setup/onboarding agent preparing the container, or the user explicitly asked to run environment setup/validation.

1. **Single-Command Idempotent Setup:**
   Execute the automated setup entrypoint from the repository root:

       ./scripts/cce-init.sh

   This single script automatically handles the entire onboarding pipeline:
   - Verifies the native Node.js runtime (`>=22` required; Node 22 and Node 24 are natively supported—NEVER install a separate `node@22` package via `npm`).
   - Installs the pinned `@railway/cli` (`v4.3.0`) binary outside the git checkout (`~/.local/bin` or `/workspace/.onboarding/bin`) and persists `PATH` in `~/.bashrc` and `~/.profile`.
   - Runs `./scripts/validate.sh` to verify executable script permissions, Bash/Node syntax, `gateway.mjs` authentication/routing smoke tests, and deterministic HMAC token derivation.
   - Performs a read-only readiness check of Shared Cloud Environment and Personal Vault variables.

2. **Strict Non-Mutation Rule (Clean Worktree):**
   - Do NOT run `chmod`, `npm install`, or modify any tracked files in the git checkout during setup.
   - Once `./scripts/cce-init.sh` exits `0` and `git status --porcelain` is empty, environment setup is complete. Stop immediately and report readiness.

---

## Context B: Multi-Project Railway Operations (Per-Chat Operational Instructions)

**Default Entry-Point Skill:** At the start of every Context B chat session, read and follow `.agents/skills/orchestrate-claude/SKILL.md` to route between Operating an existing project, Bootstrapping a new project, or Fleet Discovery.

**Trigger:** You are in an interactive chat session helping a user create, operate, or manage Railway projects.

### Step 0: Fast Session Initialization (Run Once Per Chat)

Ensure the CLI path is loaded in your shell without re-running validation:

    export PATH="/workspace/.onboarding/bin:${HOME}/.local/bin:${PATH}"
    command -v railway >/dev/null 2>&1 || ./scripts/cce-init.sh --skip-validate

**Strict Operational Rules:**
- **1 Chat Session = 1 Target Railway Project (`<project-slug>`).**
- **1 `<project-slug>` = 1 Standalone Railway Project (`rw-<project-slug>`)** with its own persistent `/workspace` volume and dedicated Cloudflare Tunnel (`https://<project-slug>.${SCL_CF_DOMAIN}`).
- **Never Mutate This Orchestrator Repo:** Never clone user application code or write project files into `/workspace/labs-cce-railway-orchestrator`. Store per-chat state in `/tmp/cce-session-<project-slug>.env` and execute all coding/file tasks remotely on the target Railway container.

---

### Workflow B1: Fleet Discovery (When No `<project-slug>` Is Specified Yet)

If the user starts a chat without naming a `<project-slug>` or asks what projects exist:

1. **List Active Cloudflare Tunnels (`rw-*`) and Railway Projects:**

       CLEAN_TOKEN=$(printf '%s' "${SCL_CF_API_TOKEN:-}" | tr -d '\r\n' | sed -E 's/^[[:space:]"'"'"']+//; s/[[:space:]"'"'"']+$//; s/^Bearer[[:space:]]+//I')
       if [ -n "${CLEAN_TOKEN}" ] && [ -n "${SCL_CF_ACCOUNT_ID:-}" ]; then
         curl -fsSL "https://api.cloudflare.com/client/v4/accounts/${SCL_CF_ACCOUNT_ID}/cfd_tunnel?is_deleted=false" \
           -H "Authorization: Bearer ${CLEAN_TOKEN}" \
           | jq -r '.result[] | select(.name | startswith("rw-")) | "\(.name)\t\(.status)\t\(.id)"'
       fi
       if [ -n "${SCL_RAILWAY_API_TOKEN:-}" ]; then
         RAILWAY_API_TOKEN="${SCL_RAILWAY_API_TOKEN}" railway list || true
       fi

2. **Ask the User:** Present the discovered `<project-slug>` names (stripping the `rw-` prefix) and ask which `<project-slug>` this chat should attach to (`operate`) or if they want to provision a new one (`bootstrap`).

---

### Workflow B2: Operate an Existing Project (`operate <project-slug>`)

Use this workflow whenever the user names an existing `<project-slug>` or asks to run code, shell commands, git operations, or file edits on `<project-slug>`. Also read `.agents/skills/operate-claude-worker/SKILL.md` if present.

1. **Bind the Chat Session to `<project-slug>`:**

       export PROJECT_SLUG="<project-slug>"
       ./scripts/cce-init.sh --mode operate --skip-cli --skip-validate
       CLEAN_DOMAIN=$(printf '%s' "${SCL_CF_DOMAIN}" | tr -d '\r\n ' | sed -E 's/^\*\.//')
       export WORKER_HOST="${PROJECT_SLUG}.${CLEAN_DOMAIN}"
       export WORKER_URL="https://${WORKER_HOST}"
       if [ -n "${SCL_MCP_BASE_SECRET:-}" ]; then
         export WORKER_TOKEN="$(./scripts/derive-token.sh "${PROJECT_SLUG}")"
       else
         export WORKER_TOKEN="${SCL_MCP_BEARER_TOKEN}"
       fi
       cat <<EOF> "/tmp/cce-session-${PROJECT_SLUG}.env"
       export PROJECT_SLUG="${PROJECT_SLUG}"
       export WORKER_HOST="${WORKER_HOST}"
       export WORKER_URL="${WORKER_URL}"
       export WORKER_TOKEN="${WORKER_TOKEN}"
       EOF

2. **Verify Worker Reachability & Health:**

       source "/tmp/cce-session-${PROJECT_SLUG}.env"
       curl -fsSL "${WORKER_URL}/health" \
         -H "CF-Access-Client-Id: ${SCL_CF_ACCESS_CLIENT_ID}" \
         -H "CF-Access-Client-Secret: ${SCL_CF_ACCESS_CLIENT_SECRET}"

   - If `/health` returns `{"ok":true,...}`, the worker is online and ready.
   - If `/health` fails (`530`, `404`, or unreachable), check if `rw-${PROJECT_SLUG}` exists in Railway. If it does not exist, ask the user if they want you to run **Workflow B3 (Bootstrap)** for `<project-slug>`.

3. **Execute Commands & File Operations Remotely on `<project-slug>`:**
   Every request to `/tmux` or `/files` MUST include all three authentication headers:
   - `-H "CF-Access-Client-Id: ${SCL_CF_ACCESS_CLIENT_ID}"`
   - `-H "CF-Access-Client-Secret: ${SCL_CF_ACCESS_CLIENT_SECRET}"`
   - `-H "Authorization: Bearer ${WORKER_TOKEN}"`

   **Remote Endpoints on `${WORKER_URL}`:**
   - **Tmux MCP (`${WORKER_URL}/tmux`):** Supergateway SSE/JSON-RPC endpoint connected to the worker's persistent `claude-work` tmux session rooted at `/workspace`. Use this to run `claude`, `git`, test suites, builds, and shell commands inside the Railway container.
   - **Filesystem MCP (`${WORKER_URL}/files`):** Supergateway SSE/JSON-RPC endpoint rooted at `/workspace`. Use this to inspect, read, create, and edit files directly on the persistent Railway volume.
   - **Human Web Terminal (`${WORKER_URL}/terminal`):** Browser `ttyd` interface attached to the live `claude-work` tmux session. Provide this URL to the user whenever they want to watch or interact with the terminal directly.

---

### Workflow B3: Bootstrap a New Isolated Railway Project (`bootstrap <project-slug>`)

Use this workflow when the user asks to create, spin up, or bootstrap a new `<project-slug>`. Also read `.agents/skills/bootstrap-railway-project/SKILL.md` if present.

1. **Verify Admin Credentials & Railway CLI Authentication:**

       export PATH="/workspace/.onboarding/bin:${HOME}/.local/bin:${PATH}"
       ./scripts/cce-init.sh --mode bootstrap --skip-validate

2. **Derive Per-Project Bearer Token & Provision Cloudflare Tunnel + DNS:**

       export PROJECT_SLUG="<project-slug>"
       export WORKER_TOKEN="$(./scripts/derive-token.sh "${PROJECT_SLUG}")"
       export CF_TUNNEL_TOKEN="$(./scripts/provision-cf-tunnel.sh "${PROJECT_SLUG}")"

   This idempotently creates Cloudflare Tunnel `rw-${PROJECT_SLUG}`, configures ingress to `http://127.0.0.1:8080`, and sets the proxied DNS CNAME `<project-slug>.${SCL_CF_DOMAIN}`.

3. **Create Isolated Railway Project (`rw-<project-slug>`), Volume, and Deploy Worker:**
   Always run `railway init` and `railway up` from a temporary directory so the orchestrator git worktree stays clean:

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
         "CLAUDE_CODE_OAUTH_TOKEN=${SCL_CLAUDE_CODE_OAUTH_TOKEN}"

       railway up --detach
       popd >/dev/null
       rm -rf "${STAGE_DIR}"

   *Security Rule:* NEVER run `railway domain`. All traffic must enter exclusively through the outbound Cloudflare Tunnel (`CF_TUNNEL_TOKEN`).

4. **Wait for Worker Health & Transition to Operate Mode:**
   Poll the worker's `/health` endpoint until Railway finishes building the container (typically 60–120 seconds):

       CLEAN_DOMAIN=$(printf '%s' "${SCL_CF_DOMAIN}" | tr -d '\r\n ' | sed -E 's/^\*\.//')
       WORKER_URL="https://${PROJECT_SLUG}.${CLEAN_DOMAIN}"
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

   Once `/health` returns `{"ok":true}`, immediately follow **Workflow B2 (Operate)** for `<project-slug>`.
