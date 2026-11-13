#!/usr/bin/env bash
set -euo pipefail

echo "1. Checking Node.js runtime version (>=22 required)..."
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
if [ "${NODE_MAJOR}" -lt 22 ]; then
  echo "ERROR: Node.js >=22 required, found $(node -v)" >&2
  exit 1
fi

echo "2. Checking executable bits on repository scripts..."
for script in \
  scripts/cce-init.sh \
  scripts/install-railway-cli.sh \
  scripts/derive-token.sh \
  scripts/provision-cf-tunnel.sh \
  scripts/validate.sh \
  templates/railway-worker/entrypoint.sh; do
  if [ ! -x "${script}" ]; then
    echo "ERROR: ${script} is not executable. Run: chmod +x ${script} && git update-index --chmod=+x ${script}" >&2
    exit 1
  fi
done

echo "3. Checking Bash syntax..."
bash -n \
  scripts/cce-init.sh \
  scripts/install-railway-cli.sh \
  scripts/derive-token.sh \
  scripts/provision-cf-tunnel.sh \
  scripts/validate.sh \
  templates/railway-worker/entrypoint.sh

echo "4. Checking Node.js syntax on gateway.mjs..."
node --check templates/railway-worker/gateway.mjs

echo "5. Running gateway.mjs unit & routing smoke tests..."
node --input-type=module << 'NODE_EOF'
import http from 'node:http';
import assert from 'node:assert/strict';

process.env.SCL_MCP_BEARER_TOKEN = 'test-secret-token-12345';
process.env.TMUX_MCP_PORT = '18001';
process.env.TTYD_PORT = '17681';

const { server } = await import('./templates/railway-worker/gateway.mjs');

const upstream = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ proxiedPath: req.url }));
});

await new Promise((r) => upstream.listen(18001, '127.0.0.1', r));
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const port = server.address().port;
const base = `http://127.0.0.1:${port}`;

try {
  const healthRes = await fetch(`${base}/health`);
  assert.equal(healthRes.status, 200);

  const unauthRes = await fetch(`${base}/tmux`);
  assert.equal(unauthRes.status, 401);

  const authRes = await fetch(`${base}/tmux`, {
    headers: { Authorization: 'Bearer test-secret-token-12345' },
  });
  assert.equal(authRes.status, 200);
  const body = await authRes.json();
  assert.equal(body.proxiedPath, '/mcp');

  const notFoundRes = await fetch(`${base}/unknown`, {
    headers: { Authorization: 'Bearer test-secret-token-12345' },
  });
  assert.equal(notFoundRes.status, 404);

  console.log('All gateway smoke tests passed!');
} finally {
  server.close();
  upstream.close();
}
NODE_EOF

echo "6. Testing deterministic token derivation..."
TEST_OUT="$(SCL_MCP_BASE_SECRET="unit-test-secret" ./scripts/derive-token.sh "sample-slug")"
if [ "${#TEST_OUT}" -ne 64 ]; then
  echo "ERROR: Expected 64-char hex token from derive-token.sh, got: ${TEST_OUT}" >&2
  exit 1
fi

echo "VALIDATION PASSED SUCCESSFULLY."
