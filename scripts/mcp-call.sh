#!/usr/bin/env bash
set -euo pipefail

PROJECT_SLUG="${1:?Usage: mcp-call.sh <project-slug> <tmux|files> <method> [params-json]}"
SERVICE="${2:?Usage: mcp-call.sh <project-slug> <tmux|files> <method> [params-json]}"
METHOD="${3:?Usage: mcp-call.sh <project-slug> <tmux|files> <method> [params-json]}"
PARAMS_JSON="${4:-{}}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "/tmp/cce-session-${PROJECT_SLUG}.env" ]; then
  # shellcheck disable=SC1090
  source "/tmp/cce-session-${PROJECT_SLUG}.env"
else
  CLEAN_DOMAIN=$(printf '%s' "${CF_DOMAIN:?CF_DOMAIN required}" | tr -d '\r\n ' | sed -E 's/^\*\.//')
  export WORKER_URL="https://${PROJECT_SLUG}.${CLEAN_DOMAIN}"
  if [ -n "${MCP_BASE_SECRET:-}" ]; then
    export WORKER_TOKEN="$("${SCRIPT_DIR}/derive-token.sh" "${PROJECT_SLUG}")"
  else
    export WORKER_TOKEN="${MCP_BEARER_TOKEN:?MCP_BEARER_TOKEN or MCP_BASE_SECRET required}"
  fi
fi

node - "${WORKER_URL}" "${SERVICE}" "${METHOD}" "${PARAMS_JSON}" << 'NODE_EOF'
const [workerUrl, service, method, paramsRaw] = process.argv.slice(2);
const params = JSON.parse(paramsRaw || "{}");

const headers = {
  "CF-Access-Client-Id": process.env.CF_ACCESS_CLIENT_ID || "",
  "CF-Access-Client-Secret": process.env.CF_ACCESS_CLIENT_SECRET || "",
  "Authorization": `Bearer ${process.env.WORKER_TOKEN}`
};

const sseUrl = `${workerUrl}/${service}/sse`;
const controller = new AbortController();
const timeout = setTimeout(() => {
  console.error("ERROR: MCP SSE request timed out after 30s");
  controller.abort();
  process.exit(1);
}, 30000);

async function main() {
  const res = await fetch(sseUrl, { headers, signal: controller.signal });
  if (!res.ok) {
    throw new Error(`SSE connect failed (${res.status}): ${await res.text()}`);
  }

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let postUrl = null;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });

    const lines = buffer.split(/\r?\n/);
    buffer = lines.pop() || "";

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (line.startsWith("data: ")) {
        const data = line.slice(6).trim();
        if (!postUrl && (data.startsWith("/") || data.startsWith("http"))) {
          postUrl = data.startsWith("http") ? data : new URL(data, workerUrl).toString();

          await fetch(postUrl, {
            method: "POST",
            headers: { ...headers, "Content-Type": "application/json" },
            body: JSON.stringify({
              jsonrpc: "2.0",
              id: 1,
              method: "initialize",
              params: {
                protocolVersion: "2024-11-05",
                capabilities: {},
                clientInfo: { name: "cce-orchestrator", version: "1.0.0" }
              }
            })
          });
        } else if (data.startsWith("{")) {
          const msg = JSON.parse(data);
          if (msg.id === 1 && postUrl) {
            await fetch(postUrl, {
              method: "POST",
              headers: { ...headers, "Content-Type": "application/json" },
              body: JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" })
            });
            await fetch(postUrl, {
              method: "POST",
              headers: { ...headers, "Content-Type": "application/json" },
              body: JSON.stringify({ jsonrpc: "2.0", id: 2, method, params })
            });
          } else if (msg.id === 2) {
            clearTimeout(timeout);
            console.log(JSON.stringify(msg.result ?? msg, null, 2));
            controller.abort();
            process.exit(msg.error ? 1 : 0);
          }
        }
      }
    }
  }
}

main().catch((err) => {
  if (err.name !== "AbortError") {
    console.error(err.message || err);
    process.exit(1);
  }
});
NODE_EOF
