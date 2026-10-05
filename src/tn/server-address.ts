export type AddressResult =
  | { ok: true; url: string }
  | { ok: false; reason: 'empty' | 'invalid' | 'insecure' | 'credentials' };

/**
 * Cleans up what a user typed into "Server verbinden".
 * The library's own network stack ignores the platform's cleartext rules, so the app has to enforce HTTPS itself:
 * plain http is accepted only when `allowInsecure` is set (development builds, local test network).
 */
export function normalizeServerAddress(input: string, options: { allowInsecure: boolean }): AddressResult {
  const text = input.trim();
  if (!text) return { ok: false, reason: 'empty' };

  const hasScheme = /^[A-Za-z][A-Za-z0-9+.-]*:\/\//.test(text);
  const candidate = hasScheme ? text : `https://${text}`;

  let url: URL;
  try {
    url = new URL(candidate);
  } catch {
    return { ok: false, reason: 'invalid' };
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return { ok: false, reason: 'invalid' };
  if (!url.hostname) return { ok: false, reason: 'invalid' };
  if (url.username || url.password) return { ok: false, reason: 'credentials' };
  if (url.protocol === 'http:' && !options.allowInsecure) return { ok: false, reason: 'insecure' };

  const path = url.pathname.replace(/\/+$/, '');
  return { ok: true, url: `${url.protocol}//${url.host}${path}` };
}
