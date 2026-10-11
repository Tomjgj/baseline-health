// Run the coach locally: serves the app at http://localhost:8787 and the coach at /api/coach on the same origin.
//   ANTHROPIC_API_KEY=... COACH_ACCESS_CODE=pick-one node dev.mjs
// Then in the app: Settings → Claude coach → address http://localhost:8787/api/coach and your access code.
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { Readable } from 'node:stream';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { handleCoach } from './coach.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const port = Number(process.env.PORT) || 8787;
const env = { ...process.env, ALLOWED_ORIGINS: process.env.ALLOWED_ORIGINS || `http://localhost:${port}` };

http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${port}`);
  if (url.pathname === '/api/coach') {
    const ac = new AbortController();
    res.on('close', () => { if (!res.writableEnded) ac.abort(); });
    const request = new Request(url, { method: req.method, headers: req.headers, body: req.method === 'POST' ? Readable.toWeb(req) : null, duplex: 'half', signal: ac.signal });
    const response = await handleCoach(request, env);
    res.writeHead(response.status, Object.fromEntries(response.headers));
    if (response.body) for await (const chunk of response.body) res.write(chunk);
    res.end();
    return;
  }
  if (url.pathname === '/' || url.pathname === '/index.html') {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(await readFile(path.join(here, '..', 'index.html')));
    return;
  }
  res.writeHead(404).end();
}).listen(port, () => console.log(`Baseline with the coach: http://localhost:${port}`));
