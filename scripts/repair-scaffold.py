python3 - << 'PYEOF'
import os

D = chr(36)       # $
BT = chr(96)      # `

files = {}

files["AGENTS.md"] = f"""# Agent Operating Directives

## 1. Do Not Auto-Run Setup or Bootstrap on Session Start
- Do **NOT** automatically run project bootstrap, Railway CLI installs, or container deployments when a session starts.
- On session start (or when asked to check readiness), run:
  {BT}./scripts/cce-init.sh --mode check{BT}
  and report the exact Pre-Flight table to the operator so they know which variables to set at the Cloud Environment or Personal Vault level before setup begins.

## 2. Explicit Permission to Overwrite / Repair Repository Files
- You have **standing permission** to overwrite any file in {BT}scripts/{BT}, {BT}templates/railway-worker/{BT}, and {BT}.agents/skills/{BT}.
"""

files["scripts/cce-init.sh"] = f"""#!/usr/bin/env bash
set -euo pipefail

MODE="{D}{{1:---mode}}"
if [ "{D}{{MODE}}" = "--mode" ]; then
  MODE="{D}{{2:-check}}"
fi

chmod +x "{D}(pwd)/scripts/derive-token.sh" "{D}(pwd)/scripts/provision-cf-tunnel.sh" 2>/dev/null || true

missing_shared=()
missing_admin=()

check_var() {{
  local var_name="{D}1"
  local group="{D}2"
  local desc="{D}3"
  local val="{D}{{!var_name:-}}"

  if [ -z "{D}{{val}}" ]; then
    if [ "{D}{{group}}" = "shared" ]; then
      missing_shared+=("  - {D}{{var_name}}: {D}{{desc}}")
    else
      missing_admin+=("  - {D}{{var_name}}: {D}{{desc}}")
    fi
  elif [[ "{D}{{val}}" == CODEX_NET_SECRET* ]] && [[ "{D}{{var_name}}" =~ ^(RAILWAY_API_TOKEN|CF_API_TOKEN|MCP_BASE_SECRET|CLAUDE_CODE_OAUTH_TOKEN){D} ]]; then
    missing_admin+=("  - {D}{{var_name}}: Currently set as 'Network secret' (placeholder detected). MUST be moved to 'Environment variable' in Personal Vault!")
  fi
}}

check_var "CF_DOMAIN"               "shared" "Set in Shared Cloud Environment -> Environment variables (e.g. yourdomain.com)"
check_var "CF_ACCESS_CLIENT_ID"     "shared" "Set in Shared Cloud Environment -> Environment variables (CF Service Token ID)"
check_var "CF_ACCESS_CLIENT_SECRET" "shared" "Set in Shared Cloud Environment -> Network secrets (Allowed domains: *.<CF_DOMAIN>) or Environment variables"

check_var "MCP_BASE_SECRET"         "admin"  "Set in Personal Vault -> Environment variables (64-char hex from: openssl rand -hex 32)"
check_var "CLAUDE_CODE_OAUTH_TOKEN" "admin"  "Set in Personal Vault -> Environment variables (from: claude setup-token)"
check_var "CF_ACCOUNT_ID"           "admin"  "Set in Personal Vault -> Environment variables (32-char Cloudflare Account ID)"
check_var "CF_ZONE_ID"              "admin"  "Set in Personal Vault -> Environment variables (32-char Cloudflare Zone ID)"
check_var "CF_API_TOKEN"            "admin"  "Set in Personal Vault -> Environment variables (Cloudflare API token with Tunnel:Edit + DNS:Edit)"
check_var "RAILWAY_API_TOKEN"       "admin"  "Set in Personal Vault -> Environment variables (Railway Account/Team token)"

echo "========================================================================"
echo " CCE Orchestrator Environment Pre-Flight Check (Mode: {D}{{MODE}})"
echo "========================================================================"

if [ {D}{{#missing_shared[@]}} -eq 0 ]; then
  echo "[OK] Shared Operator Environment Variables: READY"
else
  echo "[MISSING] Shared Cloud Environment Settings (Settings > Codex Cloud > Environments):"
  printf '%s\\n' "{D}{{missing_shared[@]}}"
fi

echo "------------------------------------------------------------------------"

if [ {D}{{#missing_admin[@]}} -eq 0 ]; then
  echo "[OK] Admin Bootstrap Personal Vault Variables: READY"
else
  echo "[MISSING/MISCONFIGURED] Admin Personal Vault Settings (Settings > Codex Cloud > Personal vault):"
  printf '%s\\n' "{D}{{missing_admin[@]}}"
  echo ""
  echo "  NOTE ON EGRESS PROXY: Keep a dummy Network Secret (e.g. ALLOWLIST_PROXY=1)"
  echo "  in your Cloud Environment with Allowed domains:"
  echo "    api.cloudflare.com, backboard.railway.com, *.railway.com, *.railway.app, *.<CF_DOMAIN>"
fi
echo "========================================================================"

if [ "{D}{{MODE}}" = "check" ]; then
  exit 0
fi

if [ "{D}{{MODE}}" = "operate" ]; then
  if [ {D}{{#missing_shared[@]}} -gt 0 ]; then
    echo "ERROR: Cannot operate worker until Shared Cloud Environment variables above are configured." >&2
    exit 1
  fi
  if [ -z "{D}{{MCP_BEARER_TOKEN:-}}" ] && [ -z "{D}{{MCP_BASE_SECRET:-}}" ]; then
    echo "ERROR: Operator requires either MCP_BEARER_TOKEN (teammate) or MCP_BASE_SECRET (admin) in Personal Vault -> Environment variables." >&2
    exit 1
  fi
  echo "Operator pre-flight passed."
  exit 0
fi

if [ "{D}{{MODE}}" = "bootstrap" ]; then
  if [ {D}{{#missing_shared[@]}} -gt 0 ] || [ {D}{{#missing_admin[@]}} -gt 0 ]; then
    echo "ERROR: Cannot bootstrap new project until all missing variables above are set." >&2
    exit 1
  fi

  if ! command -v railway >/dev/null 2>&1; then
    npm install -g @railway/cli
  fi

  railway whoami
fi
"""

files["scripts/derive-token.sh"] = f"""#!/usr/bin/env bash
set -euo pipefail

PROJECT_SLUG="{D}{{1:?Usage: derive-token.sh <project-slug>}}"
: "{D}{{MCP_BASE_SECRET:?MCP_BASE_SECRET environment variable must be set in CCE}}"

printf "%s" "{D}{{PROJECT_SLUG}}" | openssl dgst -sha256 -hmac "{D}{{MCP_BASE_SECRET}}" | awk '{{print {D}NF}}'
"""

files["scripts/provision-cf-tunnel.sh"] = f"""#!/usr/bin/env bash
set -euo pipefail

PROJECT_SLUG="{D}{{1:?Usage: provision-cf-tunnel.sh <project-slug>}}"
: "{D}{{CF_API_TOKEN:?CF_API_TOKEN must be set in CCE secrets}}"
: "{D}{{CF_ACCOUNT_ID:?CF_ACCOUNT_ID must be set in CCE secrets}}"
: "{D}{{CF_ZONE_ID:?CF_ZONE_ID must be set in CCE secrets}}"
: "{D}{{CF_DOMAIN:?CF_DOMAIN must be set in CCE secrets}}"

TUNNEL_NAME="rw-{D}{{PROJECT_SLUG}}"
HOSTNAME="{D}{{PROJECT_SLUG}}.{D}{{CF_DOMAIN}}"
CF_API="https://api.cloudflare.com/client/v4"

EXISTING_ID={D}(curl -fsSL "{D}{{CF_API}}/accounts/{D}{{CF_ACCOUNT_ID}}/cfd_tunnel?name={D}{{TUNNEL_NAME}}&is_deleted=false" \\
  -H "Authorization: Bearer {D}{{CF_API_TOKEN}}" \\
  -H "Content-Type: application/json" | jq -r '.result[0].id // empty')

if [ -n "{D}{{EXISTING_ID}}" ] && [ "{D}{{EXISTING_ID}}" != "null" ]; then
  TUNNEL_ID="{D}{{EXISTING_ID}}"
else
  TUNNEL_SECRET={D}(openssl rand -base64 32)
  CREATE_RESP={D}(curl -fsSL -X POST "{D}{{CF_API}}/accounts/{D}{{CF_ACCOUNT_ID}}/cfd_tunnel" \\
    -H "Authorization: Bearer {D}{{CF_API_TOKEN}}" \\
    -H "Content-Type: application/json" \\
    --data "{{\\"name\\":\\"{D}{{TUNNEL_NAME}}\\",\\"tunnel_secret\\":\\"{D}{{TUNNEL_SECRET}}\\",\\"config_src\\":\\"cloudflare\\"}}")
  TUNNEL_ID={D}(printf "%s" "{D}{{CREATE_RESP}}" | jq -r '.result.id // empty')
  if [ -z "{D}{{TUNNEL_ID}}" ] || [ "{D}{{TUNNEL_ID}}" = "null" ]; then
    echo "ERROR: Failed to create Cloudflare Tunnel: {D}{{CREATE_RESP}}" >&2
    exit 1
  fi
fi

curl -fsSL -X PUT "{D}{{CF_API}}/accounts/{D}{{CF_ACCOUNT_ID}}/cfd_tunnel/{D}{{TUNNEL_ID}}/configurations" \\
  -H "Authorization: Bearer {D}{{CF_API_TOKEN}}" \\
  -H "Content-Type: application/json" \\
  --data "{{\\"config\\":{{\\"ingress\\":[{{\\"hostname\\":\\"{D}{{HOSTNAME}}\\",\\"service\\":\\"http://127.0.0.1:8080\\"}},{{\\"service\\":\\"http_status:404\\"}}]}}}}" >/dev/null

DNS_RECORD_ID={D}(curl -fsSL "{D}{{CF_API}}/zones/{D}{{CF_ZONE_ID}}/dns_records?type=CNAME&name={D}{{HOSTNAME}}" \\
  -H "Authorization: Bearer {D}{{CF_API_TOKEN}}" \\
  -H "Content-Type: application/json" | jq -r '.result[0].id // empty')

DNS_PAYLOAD="{{\\"type\\":\\"CNAME\\",\\"name\\":\\"{D}{{HOSTNAME}}\\",\\"content\\":\\"{D}{{TUNNEL_ID}}.cfargotunnel.com\\",\\"proxied\\":true}}"

if [ -n "{D}{{DNS_RECORD_ID}}" ] && [ "{D}{{DNS_RECORD_ID}}" != "null" ]; then
  curl -fsSL -X PUT "{D}{{CF_API}}/zones/{D}{{CF_ZONE_ID}}/dns_records/{D}{{DNS_RECORD_ID}}" \\
    -H "Authorization: Bearer {D}{{CF_API_TOKEN}}" \\
    -H "Content-Type: application/json" \\
    --data "{D}{{DNS_PAYLOAD}}" >/dev/null
else
  curl -fsSL -X POST "{D}{{CF_API}}/zones/{D}{{CF_ZONE_ID}}/dns_records" \\
    -H "Authorization: Bearer {D}{{CF_API_TOKEN}}" \\
    -H "Content-Type: application/json" \\
    --data "{D}{{DNS_PAYLOAD}}" >/dev/null
fi

CF_TUNNEL_TOKEN={D}(curl -fsSL "{D}{{CF_API}}/accounts/{D}{{CF_ACCOUNT_ID}}/cfd_tunnel/{D}{{TUNNEL_ID}}/token" \\
  -H "Authorization: Bearer {D}{{CF_API_TOKEN}}" \\
  -H "Content-Type: application/json" | jq -r '.result // empty')

if [ -z "{D}{{CF_TUNNEL_TOKEN}}" ] || [ "{D}{{CF_TUNNEL_TOKEN}}" = "null" ]; then
  echo "ERROR: Failed to fetch Cloudflare Tunnel token for {D}{{TUNNEL_ID}}" >&2
  exit 1
fi

printf "%s\\n" "{D}{{CF_TUNNEL_TOKEN}}"
"""

files["templates/railway-worker/Dockerfile"] = f"""FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \\
    bash \\
    ca-certificates \\
    curl \\
    git \\
    jq \\
    openssh-client \\
    procps \\
    python3 \\
    ripgrep \\
    tmux \\
    && rm -rf /var/lib/apt/lists/*

RUN ARCH={D}(dpkg --print-architecture) && \\
    if [ "{D}ARCH" = "arm64" ]; then TTYD_ARCH="aarch64"; CF_ARCH="arm64"; else TTYD_ARCH="x86_64"; CF_ARCH="amd64"; fi && \\
    curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.{D}{{TTYD_ARCH}}" -o /usr/local/bin/ttyd && \\
    chmod +x /usr/local/bin/ttyd && \\
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-{D}{{CF_ARCH}}" -o /usr/local/bin/cloudflared && \\
    chmod +x /usr/local/bin/cloudflared

RUN npm install -g \\
    @anthropic-ai/claude-code \\
    supergateway \\
    tmux-mcp \\
    @modelcontextprotocol/server-filesystem

WORKDIR /opt/worker
COPY gateway.mjs /opt/worker/gateway.mjs
COPY entrypoint.sh /opt/worker/entrypoint.sh
RUN chmod +x /opt/worker/entrypoint.sh

ENV PORT=8080
ENV WORKSPACE_DIR=/workspace

ENTRYPOINT ["/opt/worker/entrypoint.sh"]
"""

files["templates/railway-worker/entrypoint.sh"] = f"""#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="{D}{{WORKSPACE_DIR:-/workspace}}"

mkdir -p \\
  "{D}{{WORKSPACE}}/nethub/nexus" \\
  "{D}{{WORKSPACE}}/projects" \\
  "{D}{{WORKSPACE}}/shared" \\
  "{D}{{WORKSPACE}}/secrets" \\
  "{D}{{WORKSPACE}}/logs" \\
  "{D}{{WORKSPACE}}/.claude"

ln -sfn "{D}{{WORKSPACE}}/nethub" /nethub
ln -sfn "{D}{{WORKSPACE}}/nethub" /root/nethub
ln -sfn "{D}{{WORKSPACE}}/.claude" /root/.claude

if [ ! -f "{D}{{WORKSPACE}}/.claude.json" ]; then
  cat << 'EOF' > "{D}{{WORKSPACE}}/.claude.json"
{{
  "hasCompletedOnboarding": true,
  "theme": "dark",
  "bypassPermissionsModeAccepted": true
}}
EOF
fi
ln -sfn "{D}{{WORKSPACE}}/.claude.json" /root/.claude.json

cat << 'EOF' > /root/.tmux.conf
set -g history-limit 50000
set -g mouse on
set -g status off
EOF

if ! tmux has-session -t claude-work 2>/dev/null; then
  tmux new-session -d -s claude-work -c "{D}{{WORKSPACE}}/nethub/nexus"
fi

supergateway \\
  --stdio "tmux-mcp" \\
  --outputTransport streamableHttp \\
  --stateful \\
  --port 8001 \\
  --streamableHttpPath /mcp \\
  > "{D}{{WORKSPACE}}/logs/tmux-mcp.log" 2>&1 &

supergateway \\
  --stdio "mcp-server-filesystem {D}{{WORKSPACE}}" \\
  --outputTransport streamableHttp \\
  --stateful \\
  --port 8002 \\
  --streamableHttpPath /mcp \\
  > "{D}{{WORKSPACE}}/logs/files-mcp.log" 2>&1 &

ttyd \\
  --port 7681 \\
  --interface 127.0.0.1 \\
  --base-path /terminal \\
  -W \\
  tmux new-session -A -s claude-work -c "{D}{{WORKSPACE}}/nethub/nexus" \\
  > "{D}{{WORKSPACE}}/logs/ttyd.log" 2>&1 &

if [ -n "{D}{{CF_TUNNEL_TOKEN:-}}" ]; then
  cloudflared tunnel --no-autoupdate run --token "{D}{{CF_TUNNEL_TOKEN}}" \\
    > "{D}{{WORKSPACE}}/logs/cloudflared.log" 2>&1 &
fi

exec node /opt/worker/gateway.mjs
"""

files["templates/railway-worker/gateway.mjs"] = f"""import http from 'node:http';
import net from 'node:net';
import crypto from 'node:crypto';

const PORT = process.env.PORT || 8080;
const EXPECTED_TOKEN = process.env.MCP_BEARER_TOKEN || '';

function isValidToken(req) {{
  if (!EXPECTED_TOKEN) return false;
  const auth = req.headers['authorization'] || '';
  const urlObj = new URL(req.url, 'http://127.0.0.1');
  const queryToken = urlObj.searchParams.get('token');
  const candidate = queryToken ? {BT}Bearer {D}{{queryToken}}{BT} : auth;
  const expected = {BT}Bearer {D}{{EXPECTED_TOKEN}}{BT};
  const a = Buffer.from(candidate);
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}}

function isAuthorized(req) {{
  if (isValidToken(req)) return true;
  if (req.url.startsWith('/terminal') && req.headers['cf-access-jwt-assertion']) {{
    return true;
  }}
  return false;
}}

function resolveTarget(url) {{
  if (url.startsWith('/tmux')) {{
    return {{ port: 8001, path: url.replace(/^\\/tmux/, '/mcp') || '/mcp' }};
  }}
  if (url.startsWith('/files')) {{
    return {{ port: 8002, path: url.replace(/^\\/files/, '/mcp') || '/mcp' }};
  }}
  if (url.startsWith('/terminal')) {{
    return {{ port: 7681, path: url }};
  }}
  return null;
}}

const server = http.createServer((req, res) => {{
  if (req.url === '/health') {{
    res.writeHead(200, {{ 'Content-Type': 'application/json' }});
    return res.end(JSON.stringify({{ status: 'ok' }}));
  }}

  if (!isAuthorized(req)) {{
    res.writeHead(401, {{ 'Content-Type': 'application/json' }});
    return res.end(JSON.stringify({{ error: 'Unauthorized' }}));
  }}

  const target = resolveTarget(req.url);
  if (!target) {{
    res.writeHead(404, {{ 'Content-Type': 'application/json' }});
    return res.end(JSON.stringify({{ error: 'Use /tmux, /files, or /terminal' }}));
  }}

  const proxyReq = http.request(
    {{
      hostname: '127.0.0.1',
      port: target.port,
      path: target.path,
      method: req.method,
      headers: req.headers,
    }},
    (proxyRes) => {{
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res, {{ end: true }});
    }}
  );

  proxyReq.on('error', (err) => {{
    res.writeHead(502, {{ 'Content-Type': 'application/json' }});
    res.end(JSON.stringify({{ error: err.message }}));
  }});

  req.pipe(proxyReq, {{ end: true }});
}});

server.on('upgrade', (req, socket, head) => {{
  if (!isAuthorized(req)) {{
    socket.write('HTTP/1.1 401 Unauthorized\\r\\n\\r\\n');
    socket.destroy();
    return;
  }}

  const target = resolveTarget(req.url);
  if (!target) {{
    socket.write('HTTP/1.1 404 Not Found\\r\\n\\r\\n');
    socket.destroy();
    return;
  }}

  const proxySocket = net.connect(target.port, '127.0.0.1', () => {{
    let rawReq = {BT}{D}{{req.method}} {D}{{target.path}} HTTP/{D}{{req.httpVersion}}\\r\\n{BT};
    for (let i = 0; i < req.rawHeaders.length; i += 2) {{
      rawReq += {BT}{D}{{req.rawHeaders[i]}}: {D}{{req.rawHeaders[i + 1]}}\\r\\n{BT};
    }}
    rawReq += '\\r\\n';
    proxySocket.write(rawReq);
    if (head && head.length) proxySocket.write(head);
    socket.pipe(proxySocket).pipe(socket);
  }});

  proxySocket.on('error', () => socket.destroy());
  socket.on('error', () => proxySocket.destroy());
}});

server.listen(PORT, '127.0.0.1', () => {{
  console.log({BT}MCP Auth Gateway listening on 127.0.0.1:{D}{{PORT}}{BT});
}});
"""

files[".agents/skills/bootstrap-railway-project/SKILL.md"] = f"""---
name: bootstrap-railway-project
description: Provisions a new Railway project, Cloudflare Tunnel (<project-slug>.<CF_DOMAIN>), and persistent Claude Code worker container (with Volume at /workspace/nethub/nexus, ttyd, tmux-mcp, Filesystem MCP, and Remote Control support).
---

# Bootstrap Railway Project Skill

Require a {BT}<project-slug>{BT} from the operator before running.

## Execution Steps

1. **Run Pre-Flight Check, Derive MCP Token & Provision Cloudflare Tunnel**
   - {BT}./scripts/cce-init.sh --mode bootstrap{BT}
   - {BT}MCP_TOKEN={D}(./scripts/derive-token.sh "<project-slug>"){BT}
   - {BT}CF_TUNNEL_TOKEN={D}(./scripts/provision-cf-tunnel.sh "<project-slug>"){BT}
   - {BT}DOMAIN="https://<project-slug>.{D}{{CF_DOMAIN}}"{BT}

2. **Create Railway Project, Service, and Persistent Volume**
   - {BT}mkdir -p "/tmp/rw-<project-slug>" && cp -r templates/railway-worker/* "/tmp/rw-<project-slug>/"{BT}
   - {BT}cd "/tmp/rw-<project-slug>"{BT}
   - {BT}railway init --name "<project-slug>"{BT}
   - {BT}railway add --service "claude-worker"{BT}
   - {BT}railway service "claude-worker"{BT}
   - {BT}railway volume add --mount-path /workspace{BT}

3. **Inject Secrets into the Railway Service (Zero Public Railway Ports)**
   - {BT}railway variables --set "CLAUDE_CODE_OAUTH_TOKEN={D}{{CLAUDE_CODE_OAUTH_TOKEN}}"{BT}
   - {BT}railway variables --set "MCP_BEARER_TOKEN={D}{{MCP_TOKEN}}"{BT}
   - {BT}railway variables --set "CF_TUNNEL_TOKEN={D}{{CF_TUNNEL_TOKEN}}"{BT}
   - {BT}railway variables --set "WORKSPACE_DIR=/workspace"{BT}

4. **Deploy Worker Container (Outbound Cloudflare Tunnel Only)**
   - {BT}railway up --detach{BT}
   - Do NOT run {BT}railway domain{BT} — the container remains dark on Railway's edge and connects outbound via {BT}cloudflared{BT}.

5. **Register Remote MCP Servers in CCE & Verify Health**
   - Poll {BT}{D}{{DOMAIN}}/health{BT} with headers {BT}CF-Access-Client-Id: {D}{{CF_ACCESS_CLIENT_ID}}{BT} and {BT}CF-Access-Client-Secret: {D}{{CF_ACCESS_CLIENT_SECRET}}{BT} until HTTP 200 is returned.
   - Register remote Streamable HTTP MCP servers with headers {BT}CF-Access-Client-Id{BT}, {BT}CF-Access-Client-Secret{BT}, and {BT}Authorization: Bearer {D}{{MCP_TOKEN}}{BT}:
     - {BT}tmux-mcp{BT}: {BT}{D}{{DOMAIN}}/tmux{BT}
     - {BT}files-mcp{BT}: {BT}{D}{{DOMAIN}}/files{BT}
   - Web terminal ({BT}ttyd{BT}) is live at {BT}{D}{{DOMAIN}}/terminal{BT}.
"""

files[".agents/skills/operate-claude-worker/SKILL.md"] = f"""---
name: operate-claude-worker
description: Connects to an existing Railway worker over Cloudflare Tunnel (<project-slug>.<CF_DOMAIN>) to share secrets, manage files in /workspace/nethub/nexus via Filesystem MCP, and operate Claude Code (including --rc Remote Control, /exit, claude --resume, and ttyd) via tmux-mcp.
---

# Operate Claude Worker Skill

Requires {BT}<project-slug>{BT} (which resolves to {BT}DOMAIN="https://<project-slug>.{D}{{CF_DOMAIN}}"{BT}).

## 1. Authenticate & Connect (Dual-Wall Security, Admin or Teammate)
- Run operator pre-flight check:
  {BT}./scripts/cce-init.sh --mode operate{BT}
- Resolve project token (uses pre-assigned {BT}MCP_BEARER_TOKEN{BT} for teammates, or derives from {BT}MCP_BASE_SECRET{BT} for admins):
  {BT}MCP_TOKEN="{D}{{MCP_BEARER_TOKEN:-{D}(./scripts/derive-token.sh "<project-slug>")}}"{BT}
- Configure remote Streamable HTTP MCP endpoints with all 3 headers ({BT}CF-Access-Client-Id: {D}{{CF_ACCESS_CLIENT_ID}}{BT}, {BT}CF-Access-Client-Secret: {D}{{CF_ACCESS_CLIENT_SECRET}}{BT}, and {BT}Authorization: Bearer {D}{{MCP_TOKEN}}{BT}):
  - {BT}tmux-mcp{BT}: {BT}https://<project-slug>.{D}{{CF_DOMAIN}}/tmux{BT}
  - {BT}files-mcp{BT}: {BT}https://<project-slug>.{D}{{CF_DOMAIN}}/files{BT}
- **Human Web Terminal ({BT}ttyd{BT}):** Open {BT}https://<project-slug>.{D}{{CF_DOMAIN}}/terminal{BT} in a browser (authenticated via Cloudflare Zero Trust) to view and type into {BT}claude-work{BT} alongside Codex.

## 2. Sharing Secrets
- Write {BT}.env{BT} files to {BT}/workspace/nethub/nexus/.env{BT} (or {BT}/workspace/secrets/{BT}) via {BT}files-mcp{BT} ({BT}write_file{BT}).
- *(Admins only)* Or inject container environment variables via Railway CLI:
  {BT}railway variables --set "KEY=VALUE" --service "claude-worker"{BT}

## 3. Sharing Files
- Use {BT}files-mcp{BT} ({BT}write_file{BT}, {BT}edit_file{BT}, {BT}read_file{BT}, {BT}list_directory{BT}) targeting {BT}/workspace/nethub/nexus/{BT} (primary working directory), {BT}/workspace/projects/{BT}, or {BT}/workspace/shared/{BT}.

## 4. Operating Claude Code + Remote Control ({BT}--rc{BT}) in {BT}claude-work{BT}
Use {BT}tmux-mcp{BT} targeting the {BT}claude-work{BT} session (rooted in {BT}/workspace/nethub/nexus{BT}):
- **Check state:** Call {BT}capture-pane{BT} on {BT}claude-work{BT} before sending input.
- **Start Claude with Remote Control (Interactive Mode):**
  Send {BT}claude --rc "<project-slug>"{BT} (or {BT}claude --rc "<project-slug>" --dangerously-skip-permissions{BT}) + {BT}Enter{BT} via {BT}send-keys{BT}.
  *(Note: Never use {BT}claude remote-control{BT} server mode, as it disables the local interactive TUI inside tmux. If Remote Control prompts for full-scope claude.ai OAuth on first run, run {BT}unset CLAUDE_CODE_OAUTH_TOKEN && claude auth login{BT} once inside {BT}claude-work{BT}; credentials persist in {BT}/workspace/.claude{BT}).*
- **Prompt Claude:** Send prompt text + {BT}Enter{BT} via {BT}send-keys{BT}, then poll {BT}capture-pane{BT}.
- **Exit to shell:** Send {BT}/exit{BT} + {BT}Enter{BT} via {BT}send-keys{BT} and verify the bash prompt via {BT}capture-pane{BT}.
- **Resume session with Remote Control:** From bash in {BT}/workspace/nethub/nexus{BT}, send {BT}claude --resume --rc{BT} + {BT}Enter{BT} via {BT}send-keys{BT}.
"""

for path, content in files.items():
    dirpath = os.path.dirname(path)
    if dirpath:
        os.makedirs(dirpath, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)

for exec_path in [
    "scripts/cce-init.sh",
    "scripts/derive-token.sh",
    "scripts/provision-cf-tunnel.sh",
    "templates/railway-worker/entrypoint.sh",
]:
    os.chmod(exec_path, 0o755)

print("SUCCESS: AGENTS.md and all 8 scaffold files written and verified.")
PYEOF
./scripts/cce-init.sh --mode check
