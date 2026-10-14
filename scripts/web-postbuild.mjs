// Turns the Expo web export into the installable web app: manifest, service worker, the client library next to the app,
// icons, tones, Content-Security-Policy, and the files GitHub Pages needs.
//
//   EXPO_BASE_URL=/TN-App node scripts/web-postbuild.mjs dist-web
//
// Dependency-free on purpose (plain node). Reads the export, writes into the same folder.
import { createHash } from 'node:crypto';
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join, relative, sep } from 'node:path';

const dist = process.argv[2] ?? 'dist-web';
const base = (process.env.EXPO_BASE_URL ?? '').replace(/\/+$/, ''); // '' or '/TN-App'
const root = new URL('..', import.meta.url).pathname;
const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));

const indexPath = join(dist, 'index.html');
if (!existsSync(indexPath)) throw new Error(`${indexPath} not found: run "expo export --platform web --output-dir ${dist}" first`);

// ---- files that belong next to the app ----
const lib = join(root, 'node_modules/@trafficnetwork/client-web');
for (const [from, to] of [
  ['index.js', 'tnlib/index.js'],
  ['shared/index.js', 'tnlib/shared/index.js'],
  ['pkg/trafficnetwork_wasm.js', 'tnlib/pkg/trafficnetwork_wasm.js'],
  ['pkg/trafficnetwork_wasm_bg.wasm', 'tnlib/pkg/trafficnetwork_wasm_bg.wasm'],
  ['package.json', 'tnlib/package.json'],
  ['LICENSE', 'tnlib/LICENSE'],
]) {
  mkdirSync(join(dist, to, '..'), { recursive: true });
  cpSync(join(lib, from), join(dist, to));
}
// the map library: loaded when the map first shows, not part of the main bundle
mkdirSync(join(dist, 'maplibre'), { recursive: true });
for (const file of ['maplibre-gl.js', 'maplibre-gl.css']) cpSync(join(root, 'node_modules/maplibre-gl/dist', file), join(dist, 'maplibre', file));
cpSync(join(root, 'node_modules/maplibre-gl/LICENSE.txt'), join(dist, 'maplibre', 'LICENSE.txt'));
cpSync(join(root, 'assets/web/tnlib-loader.js'), join(dist, 'tnlib-loader.js'));
cpSync(join(root, 'assets/sounds'), join(dist, 'sounds'), { recursive: true });
cpSync(join(root, 'assets/pwa'), join(dist, 'icons'), { recursive: true });
writeFileSync(join(dist, '.nojekyll'), '');

// ---- manifest ----
const manifest = {
  id: `${base}/`,
  name: 'TNViewer',
  short_name: 'TNViewer',
  description: 'Verkehrsmeldungen und Tempolimits des Trafficnetwork (Testversion)',
  lang: 'de',
  start_url: `${base}/`,
  scope: `${base}/`,
  display: 'standalone',
  display_override: ['fullscreen', 'standalone'],
  orientation: 'any',
  background_color: '#FFFFFF',
  theme_color: '#FFFFFF',
  icons: [
    { src: `${base}/icons/icon-192.png`, sizes: '192x192', type: 'image/png', purpose: 'any' },
    { src: `${base}/icons/icon-512.png`, sizes: '512x512', type: 'image/png', purpose: 'any' },
    { src: `${base}/icons/icon-maskable-512.png`, sizes: '512x512', type: 'image/png', purpose: 'maskable' },
  ],
};
writeFileSync(join(dist, 'manifest.webmanifest'), JSON.stringify(manifest, null, 2));

// ---- index.html ----
let html = readFileSync(indexPath, 'utf8');
const inlineStyles = [...html.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/g)].map((m) => m[1]);
const csp = [
  "default-src 'self'",
  "script-src 'self' 'wasm-unsafe-eval'",
  // React Native Web writes its styles at run time; style attributes cannot run code
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob: https:",
  "font-src 'self' data:",
  // the server is whatever the user enters, over https/wss only. WEB_CONNECT_EXTRA is for the automated tests
  // (their mock server speaks plain http on localhost) and is never set for the published build.
  `connect-src 'self' https: wss:${process.env.WEB_CONNECT_EXTRA ? ` ${process.env.WEB_CONNECT_EXTRA}` : ''}`,
  "worker-src 'self' blob:",
  "manifest-src 'self'",
  "base-uri 'self'",
  "form-action 'none'",
  "object-src 'none'",
].join('; ');
const head = [
  `<meta http-equiv="Content-Security-Policy" content="${csp}">`,
  '<meta name="referrer" content="no-referrer">',
  `<link rel="manifest" href="${base}/manifest.webmanifest">`,
  `<link rel="icon" type="image/png" sizes="32x32" href="${base}/icons/favicon-32.png">`,
  `<link rel="apple-touch-icon" href="${base}/icons/apple-touch-icon-180.png">`,
  '<meta name="apple-mobile-web-app-capable" content="yes">',
  '<meta name="mobile-web-app-capable" content="yes">',
  '<meta name="apple-mobile-web-app-title" content="TNViewer">',
  '<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">',
  '<meta name="theme-color" media="(prefers-color-scheme: light)" content="#FFFFFF">',
  '<meta name="theme-color" media="(prefers-color-scheme: dark)" content="#000000">',
  '<meta name="color-scheme" content="light dark">',
  `<script src="${base}/tnlib-loader.js"></script>`,
].join('\n    ');
html = html.replace(/<head>/i, `<head>\n    ${head}`);
// the viewport must reach under the notch (safe-area insets) for a full-screen app
html = html.replace(/<meta name="viewport" content="([^"]*)"/i, (all, content) => (content.includes('viewport-fit') ? all : `<meta name="viewport" content="${content}, viewport-fit=cover"`));
html = html.replace(/<html([^>]*)>/i, (all, attrs) => (/\blang=/.test(attrs) ? all : `<html lang="de"${attrs}>`));
writeFileSync(indexPath, html);
writeFileSync(join(dist, '404.html'), html); // GitHub Pages: a reload on a deep link still starts the app

// ---- service worker: precache everything of the app, version = hash of the files ----
function walk(dir) {
  return readdirSync(dir).flatMap((name) => {
    const full = join(dir, name);
    return statSync(full).isDirectory() ? walk(full) : [full];
  });
}
const files = walk(dist)
  .map((f) => relative(dist, f).split(sep).join('/'))
  .filter((f) => f !== 'sw.js' && f !== '404.html' && f !== '.nojekyll' && !f.endsWith('.map'))
  .sort();
const hash = createHash('sha256');
for (const f of files) hash.update(f).update(readFileSync(join(dist, f)));
const build = hash.digest('hex').slice(0, 12);
const precache = [`${base}/`, ...files.map((f) => `${base}/${f}`)];

writeFileSync(
  join(dist, 'sw.js'),
  `// TNViewer Web service worker. Generated by scripts/web-postbuild.mjs; build ${build}.
// Offline shell: the app's own files are cached when this version installs and served from the cache.
// A new version waits until the page asks for it (the "Aktualisieren" button), so a running visit is never swapped.
// It never touches requests to other origins: the server's API stays entirely the library's business.
const CACHE = 'tnviewer-${build}';
const PRECACHE = ${JSON.stringify(precache)};
const SHELL = '${base}/';

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(PRECACHE)));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k.startsWith('tnviewer-') && k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  event.respondWith(
    caches.open(CACHE).then(async (cache) => {
      const hit = await cache.match(request, { ignoreSearch: true });
      if (hit) return hit;
      if (request.mode === 'navigate') return (await cache.match(SHELL)) ?? fetch(request);
      return fetch(request);
    }),
  );
});
`,
);
writeFileSync(join(dist, 'version.json'), JSON.stringify({ app: pkg.version, build, library: JSON.parse(readFileSync(join(lib, 'package.json'), 'utf8')).version }, null, 2));
console.log(`web app ready in ${dist}: base "${base || '/'}", build ${build}, ${precache.length} precached files, ${inlineStyles.length} inline style block(s)`);
