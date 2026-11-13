# CCE Railway Multi-Project Orchestrator

Control plane for provisioning and operating isolated **Claude Code** worker environments on **Railway** from **Codex Cloud**.

In this architecture, **1 Codex Chat Session = 1 Target Railway Project (`<project-slug>`)**. Every worker runs in its own standalone Railway project (`rw-<project-slug>`) with a dedicated persistent `/workspace` volume, zero public Railway ports, and an outbound **Cloudflare Tunnel** (`https://<project-slug>.<SCL_CF_DOMAIN>`) secured by **Cloudflare Zero Trust Access** and an internal HMAC-SHA256 Bearer token reverse proxy (`gateway.mjs`).

---

## 1. Per-Chat Operational Workflows (Daily Usage)

Every new chat session loads `.agents/skills/orchestrate-claude/SKILL.md`, which immediately prompts you to choose between **Operate (1)**, **Bootstrap (2)**, or **Fleet Discovery (3)** (or jumps straight to your choice if you already named a `<project-slug>`).

Open a new chat in Codex Cloud and tell the agent which `<project-slug>` you want to work on. `AGENTS.md` automatically routes the chat to the right operational workflow:

### A. Operate an Existing Project (`operate <project-slug>`)
When you name an existing `<project-slug>` (e.g., *"Attach to billing-api and run the test suite"* or *"operate billing-api"*):
1. The agent derives the project's deterministic bearer token (`./scripts/derive-token.sh <project-slug>`).
2. It verifies container and tunnel health at `https://<project-slug>.<SCL_CF_DOMAIN>/health`.
3. It executes all shell, git, Claude Code, and file tasks remotely inside that Railway container's `/workspace` volume via its authenticated `/tmux` and `/files` MCP endpoints.

### B. Bootstrap a New Isolated Project (`bootstrap <project-slug>`)
When you ask to create a new worker (e.g., *"bootstrap auth-service"*):
1. **Token Derivation:** Derives a unique HMAC-SHA256 bearer token for `<project-slug>`.
2. **Cloudflare Tunnel & DNS:** Runs `./scripts/provision-cf-tunnel.sh <project-slug>` to create tunnel `rw-<project-slug>`, route ingress to `http://127.0.0.1:8080`, and create the proxied DNS CNAME `<project-slug>.<SCL_CF_DOMAIN>`.
3. **Isolated Railway Project:** Stages `templates/railway-worker/` in a temporary directory, creates standalone Railway project `rw-<project-slug>`, attaches a persistent volume at `/workspace`, injects secrets, and deploys via `railway up --detach`.
4. **Auto-Attach:** Polls `https://<project-slug>.<SCL_CF_DOMAIN>/health` until online, then automatically transitions the chat into **Operate** mode.

### C. Fleet Discovery
If you start a chat without naming a project (e.g., *"What projects are running?"*), the agent queries active `rw-*` Cloudflare Tunnels and Railway projects, reports their health status, and asks which `<project-slug>` to attach to.

---

## 2. Worker Container Architecture (`templates/railway-worker/`)

Each `<project-slug>` worker container runs `entrypoint.sh`, which launches four internal processes behind `cloudflared`:

| Public Tunnel Path | Internal Target | Service | Authentication Required |
| :--- | :--- | :--- | :--- |
| `https://<slug>.<SCL_CF_DOMAIN>/health` | `127.0.0.1:8080` | `gateway.mjs` health check | Cloudflare Access Service Token |
| `https://<slug>.<SCL_CF_DOMAIN>/tmux` | `127.0.0.1:8001` | Supergateway + `tmux-mcp` (`claude-work` session) | CF Access + `Authorization: Bearer <PROJECT_TOKEN>` |
| `https://<slug>.<SCL_CF_DOMAIN>/files` | `127.0.0.1:8002` | Supergateway + `@modelcontextprotocol/server-filesystem` (`/workspace`) | CF Access + `Authorization: Bearer <PROJECT_TOKEN>` |
| `https://<slug>.<SCL_CF_DOMAIN>/terminal` | `127.0.0.1:7681` | `ttyd` live browser terminal (`claude-work` session) | CF Access (`Cf-Access-Jwt-Assertion`) or Bearer Token |

*Note: `railway domain` is never used. The container has no public Railway URL; all traffic enters exclusively through the Cloudflare Tunnel.*

---

## 3. One-Time Codex Cloud Environment Setup

When a Codex Cloud container boots (or when the Setup Agent initializes the environment), it runs a single idempotent command:

    ./scripts/cce-init.sh

What `./scripts/cce-init.sh` does automatically during environment setup:
- Verifies the native Node.js runtime (`>=22` required; Node 22 and Node 24 are natively supported without extra `npm` runtime installs).
- Installs the pinned `@railway/cli` (`v4.3.0`) binary outside the git checkout (`~/.local/bin` or `/workspace/.onboarding/bin`) and persists `PATH` in `~/.bashrc` and `~/.profile` so the git worktree remains 100% clean.
- Runs `./scripts/validate.sh` to verify executable script permissions (`100755`), Bash/Node syntax, `gateway.mjs` HTTP/WebSocket auth routing smoke tests, and deterministic token derivation.
- Checks Shared Cloud Environment and Personal Vault readiness.

### Required Codex Cloud Variables

#### A. Shared Cloud Environment (`Settings > Codex Cloud > Environments`)
| Variable | Type | Value / Notes |
| :--- | :--- | :--- |
| `SCL_CF_DOMAIN` | `Environment variable` | Root Cloudflare zone (e.g., `mytunnels.fyi` — no `*.` prefix) |
| `SCL_CF_ACCESS_CLIENT_ID` | `Environment variable` | Cloudflare Access Service Token Client ID |
| `SCL_CF_ACCESS_CLIENT_SECRET` | `Network secret` *(or `Environment variable`)* | Cloudflare Access Service Token Secret (Allowed domains: `*.mytunnels.fyi`) |
| `ALLOWLIST_PROXY` | `Network secret` | Set value to `1`. Allowed domains: `api.cloudflare.com, backboard.railway.com, *.railway.com, *.railway.app, *.mytunnels.fyi` |

#### B. Admin Personal Vault (`Settings > Codex Cloud > Personal vault`)
Must be saved as **`Environment variables`** (never `Network secrets`, which inject `CODEX_NET_SECRET_...` proxy placeholders that break CLI tools):
- `SCL_RAILWAY_API_TOKEN` — Railway Account/Workspace API token
- `SCL_CF_API_TOKEN` — Cloudflare API token with **Account: Cloudflare Tunnel: Edit** and **Zone: DNS: Edit**
- `SCL_CF_ACCOUNT_ID` — Cloudflare Account ID
- `SCL_CF_ZONE_ID` — Cloudflare Zone ID for `SCL_CF_DOMAIN`
- `SCL_MCP_BASE_SECRET` — Master HMAC secret (`openssl rand -hex 32`)
- `SCL_CLAUDE_CODE_OAUTH_TOKEN` — Headless Claude Code token (`claude setup-token`)

#### C. Teammate / Operator Personal Vault (Operate-Only Users)
- `SCL_MCP_BEARER_TOKEN` — Project-specific token generated by an admin via `./scripts/derive-token.sh <project-slug>`

---

## 4. Repository Structure & CLI Reference

- `AGENTS.md` — Dual-context directives (Context A for one-time environment setup; Context B for per-chat multi-project operations).
- `scripts/cce-init.sh` — Idempotent environment setup, CLI installer trigger, validator runner, and secret pre-flight checker (`--mode setup|check|operate|bootstrap`).
- `scripts/install-railway-cli.sh` — Installs pinned Railway CLI (`v4.3.0`) outside the git checkout.
- `scripts/derive-token.sh <project-slug>` — Derives the deterministic HMAC-SHA256 bearer token for `<project-slug>`.
- `scripts/provision-cf-tunnel.sh <project-slug>` — Idempotently creates/updates Cloudflare Tunnel `rw-<project-slug>` and DNS CNAME `<project-slug>.<SCL_CF_DOMAIN>`.
- `scripts/validate.sh` — Offline CI and local smoke test suite for scripts and `gateway.mjs`.
- `templates/railway-worker/` — Dockerfile, `gateway.mjs`, and `entrypoint.sh` deployed to each isolated Railway worker project.
