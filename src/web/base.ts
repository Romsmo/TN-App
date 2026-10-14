/** Where the web app is served from, ending in a slash: the folder of `tnlib-loader.js` (a sub-path on GitHub Pages). */
export function appBase(): string {
  const configured = (globalThis as { __tnBase?: string }).__tnBase; // set by tnlib-loader.js from its own address
  return (configured ?? new URL('./', globalThis.location?.href ?? 'http://localhost/').href).replace(/\/?$/, '/');
}
