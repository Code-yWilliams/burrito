const http = require('http');
const { Pool } = require('pg');

// Connection settings come from the standard PG* env vars
// (PGHOST, PGUSER, PGPASSWORD, PGDATABASE), set by the Helm chart.
const pool = new Pool({ connectionTimeoutMillis: 3000 });
const port = process.env.PORT || 3000;

const server = http.createServer(async (req, res) => {
  if (req.method === 'GET' && req.url === '/version') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ version: require('./package.json').version }));
    return;
  }
  if (req.method === 'GET' && req.url === '/healthz') {
    try {
      await pool.query('SELECT 1');
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'ok', db: 'ok' }));
    } catch (err) {
      res.writeHead(503, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'degraded', db: 'unreachable' }));
    }
    return;
  }
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'not found' }));
});

server.listen(port, () => {
  console.log(`burrito listening on :${port}`);
});

process.on('SIGTERM', () => {
  server.close(() => {
    pool.end().then(() => process.exit(0));
  });
});
