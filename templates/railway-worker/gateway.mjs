import http from 'node:http';

const PORT = process.env.PORT || 8080;

const EXPECTED_TOKEN = process.env.MCP_BEARER_TOKEN || '';

const server = http.createServer((req, res) => {

  if (req.url === '/health') {

    res.writeHead(200, { 'Content-Type': 'application/json' });

    return res.end(JSON.stringify({ status: 'ok' }));

  }

  const auth = req.headers['authorization'] || '';

  if (!EXPECTED_TOKEN || auth !== `Bearer ${EXPECTED_TOKEN}`) {

    res.writeHead(401, { 'Content-Type': 'application/json' });

    return res.end(JSON.stringify({ error: 'Unauthorized' }));

  }

  let targetPort = null;

  let targetPath = req.url;

  if (req.url.startsWith('/tmux')) {

    targetPort = 8001;

    targetPath = req.url.replace(/^\/tmux/, '/mcp') || '/mcp';

  } else if (req.url.startsWith('/files')) {

    targetPort = 8002;

    targetPath = req.url.replace(/^\/files/, '/mcp') || '/mcp';

  } else {

    res.writeHead(404, { 'Content-Type': 'application/json' });

    return res.end(JSON.stringify({ error: 'Use /tmux or /files' }));

  }

  const proxyReq = http.request(

    {

      hostname: '127.0.0.1',

      port: targetPort,

      path: targetPath,

      method: req.method,

      headers: req.headers,

    },

    (proxyRes) => {

      res.writeHead(proxyRes.statusCode, proxyRes.headers);

      proxyRes.pipe(res, { end: true });

    }

  );

  proxyReq.on('error', (err) => {

    res.writeHead(502, { 'Content-Type': 'application/json' });

    res.end(JSON.stringify({ error: err.message }));

  });

  req.pipe(proxyReq, { end: true });

});

server.listen(PORT, '0.0.0.0', () => {

  console.log(`MCP Auth Gateway listening on port ${PORT}`);

});
