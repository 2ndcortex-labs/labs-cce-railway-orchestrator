# CCE Railway Orchestrator

Orchestrates ephemeral and persistent **Claude Code** worker containers on **Railway**, exposed exclusively over outbound **Cloudflare Tunnels** (`<project-slug>.<CF_DOMAIN>`) and protected by **Cloudflare Zero Trust Access** plus a local Node.js HMAC bearer token gateway (`gateway.mjs`).

---

## Architecture Overview

Each provisioned worker container runs without public Railway ports (`railway domain` is never used). All traffic enters through an outbound `cloudflared` tunnel to `127.0.0.1:8080` (`gateway.mjs`), which authenticates requests and routes to internal services:

| Route | Upstream Port | Service | Authentication Required |
| :--- | :--- | :--- | :--- |
| `/health` | `8080` | Gateway health check | Cloudflare Access Service Token |
| `/tmux` | `8001` | `supergateway` → `tmux-mcp` | Cloudflare Access + `Authorization: Bearer <MCP_TOKEN>` |
| `/files` | `8002` | `supergateway` → `mcp-server-filesystem` (`/workspace`) | Cloudflare Access + `Authorization: Bearer <MCP_TOKEN>` |
| `/terminal` | `7681` | `ttyd` web terminal (`claude-work` tmux session) | Cloudflare Access JWT (`cf-access-jwt-assertion`) or Bearer token |

---

## 1. Local & CI Validation (No Credentials Required)

Requires **Node.js >= 22** (supports Node 22 and Node 24), `bash`, `openssl`, `curl`, and `jq`.

Run the validation suite to verify executable bits, Bash syntax, Node.js syntax, `gateway.mjs` authentication/routing smoke tests, and deterministic HMAC token derivation:

```bash
./scripts/validate.sh
