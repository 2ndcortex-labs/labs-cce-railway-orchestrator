#!/usr/bin/env bash
set -euo pipefail

echo "1. Checking Bash syntax..."
bash -n \
  scripts/cce-init.sh \
  scripts/install-railway-cli.sh \
  scripts/derive-token.sh \
  scripts/provision-cf-tunnel.sh \
  templates/railway-worker/entrypoint.sh

echo "2. Checking Node.js syntax on gateway.mjs..."
node --check templates/railway-worker/gateway.mjs

echo "3. Running gateway.mjs unit & routing smoke tests..."
node - << 'EOF'
import http from 'node:http';
import assert from 'node:assert/strict';

process.env.MCP_BEARER_TOKEN = 'test-secret-token-12345';
process.env.TMUX_MCP_PORT = '18001';
process.env.TTYD_PORT = '17681';

const { server } = await import('./templates/railway-worker/gateway.mjs');

// Mock upstream server for tmux-mcp (18001)
const upstream = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ proxiedPath: req.url }));
});

await new Promise((r) => upstream.listen(18001, '127.0.0.1', r));
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const port = server.address().port;
const base = `http://127.0.0.1:${port}`;

try {
  // Test 1: /health is public 200
  const healthRes = await fetch(`${base}/health`);
  assert.equal(healthRes.status, 200);

  // Test 2: Unauthenticated /tmux returns 401
  const unauthRes = await fetch(`${base}/tmux`);
  assert.equal(unauthRes.status, 401);

  // Test 3: Valid Bearer token routes /tmux -> upstream /mcp (200)
  const authRes = await fetch(`${base}/tmux`, {
    headers: { Authorization: 'Bearer test-secret-token-12345' },
  });
  assert.equal(authRes.status, 200);
  const body = await authRes.json();
  assert.equal(body.proxiedPath, '/mcp');

  // Test 4: Unknown route with valid auth returns 404
  const notFoundRes = await fetch(`${base}/unknown`, {
    headers: { Authorization: 'Bearer test-secret-token-12345' },
  });
  assert.equal(notFoundRes.status, 404);

  console.log('All gateway smoke tests passed!');
} finally {
  server.close();
  upstream.close();
}
EOF

echo "4. Testing deterministic token derivation..."
TEST_OUT="$(MCP_BASE_SECRET="unit-test-secret" ./scripts/derive-token.sh "sample-slug")"
if [ "${#TEST_OUT}" -ne 64 ]; then
  echo "ERROR: Expected 64-char hex token from derive-token.sh, got: ${TEST_OUT}" >&2
  exit 1
fi

echo "VALIDATION PASSED SUCCESSFULLY."
