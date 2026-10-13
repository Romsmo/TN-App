// A tiny static server for the exported web app, with the sub-path of the real host (default /TN-App).
//   node scripts/web-serve.mjs dist-web [port] [subpath]
// For local trials and the Playwright tests; not a deployment tool.
import { createServer } from 'node:http';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { extname, join, normalize } from 'node:path';

const dist = process.argv[2] ?? 'dist-web';
const port = Number(process.argv[3] ?? process.env.PORT ?? 4173);
const sub = (process.argv[4] ?? process.env.SUBPATH ?? '/TN-App').replace(/\/+$/, '');

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json',
  '.webmanifest': 'application/manifest+json',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.wav': 'audio/wav',
  '.ttf': 'font/ttf',
  '.css': 'text/css; charset=utf-8',
};

createServer((req, res) => {
  const path = decodeURIComponent((req.url ?? '/').split('?')[0]);
  if (path !== sub && !path.startsWith(`${sub}/`)) {
    res.writeHead(404).end('not found');
    return;
  }
  const rel = normalize(path.slice(sub.length) || '/').replace(/^(\.\.[/\\])+/, '');
  let file = join(dist, rel);
  if (existsSync(file) && statSync(file).isDirectory()) file = join(file, 'index.html');
  // like GitHub Pages: an unknown path answers with 404.html (which is the app)
  const found = existsSync(file);
  const target = found ? file : join(dist, '404.html');
  res.writeHead(found ? 200 : 404, { 'content-type': TYPES[extname(target)] ?? 'application/octet-stream', 'cache-control': 'no-cache' });
  res.end(readFileSync(target));
}).listen(port, () => console.log(`http://localhost:${port}${sub}/`));
