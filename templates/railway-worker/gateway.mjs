import http from 'node:http';
import net from 'node:net';
import crypto from 'node:crypto';

const PORT = Number(process.env.PORT ?? 8080);
const HOST = process.env.HOST || '127.0.0.1';
const EXPECTED_TOKEN = process.env.MCP_BEARER_TOKEN || '';

export function isValidToken(req) {
  if (!EXPECTED_TOKEN) return false;
  const auth = req.headers['authorization'] || '';
  const urlObj = new URL(req.url || '/', 'http://127.0.0.1');
  const queryToken = urlObj.searchParams.get('token');
  const candidate = queryToken ? `Bearer ${queryToken}` : auth;
  const expected = `Bearer ${EXPECTED_TOKEN}`;
  const a = Buffer.from(candidate);
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

export function isAuthorized(req) {
  if (isValidToken(req)) return true;
  if ((req.url || '').startsWith('/terminal') && req.headers['cf-access-jwt-assertion']) {
    return true;
  }
  return false;
}

export function resolveTarget(url = '') {
  if (url.startsWith('/tmux')) {
    return { port: Number(process.env.TMUX_MCP_PORT || 8001), path: url.replace(/^\/tmux/, '/mcp') || '/mcp' };
  }
  if (url.startsWith('/files')) {
    return { port: Number(process.env.FILES_MCP_PORT || 8002), path: url.replace(/^\/files/, '/mcp') || '/mcp' };
  }
  if (url.startsWith('/terminal')) {
    return { port: Number(process.env.TTYD_PORT || 7681), path: url };
  }
  return null;
}

export const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ status: 'ok' }));
  }

  if (!isAuthorized(req)) {
    res.writeHead(401, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ error: 'Unauthorized' }));
  }

  const target = resolveTarget(req.url);
  if (!target) {
    res.writeHead(404, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ error: 'Use /tmux, /files, or /terminal' }));
  }

  const proxyReq = http.request(
    {
      hostname: '127.0.0.1',
      port: target.port,
      path: target.path,
      method: req.method,
      headers: req.headers,
    },
    (proxyRes) => {
      res.writeHead(proxyRes.statusCode || 502, proxyRes.headers);
      proxyRes.pipe(res, { end: true });
    }
  );

  proxyReq.on('error', (err) => {
    res.writeHead(502, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: err.message }));
  });

  req.pipe(proxyReq, { end: true });
});

server.on('upgrade', (req, socket, head) => {
  if (!isAuthorized(req)) {
    socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
    socket.destroy();
    return;
  }

  const target = resolveTarget(req.url);
  if (!target) {
    socket.write('HTTP/1.1 404 Not Found\r\n\r\n');
    socket.destroy();
    return;
  }

  const proxySocket = net.connect(target.port, '127.0.0.1', () => {
    let rawReq = `${req.method} ${target.path} HTTP/${req.httpVersion}\r\n`;
    for (let i = 0; i < req.rawHeaders.length; i += 2) {
      rawReq += `${req.rawHeaders[i]}: ${req.rawHeaders[i + 1]}\r\n`;
    }
    rawReq += '\r\n';
    proxySocket.write(rawReq);
    if (head && head.length) proxySocket.write(head);
    socket.pipe(proxySocket).pipe(socket);
  });

  proxySocket.on('error', () => socket.destroy());
  socket.on('error', () => proxySocket.destroy());
});

if (import.meta.url === `file://${process.argv[1]}`) {
  server.listen(PORT, HOST, () => {
    console.log(`MCP Auth Gateway listening on ${HOST}:${PORT}`);
  });
}
