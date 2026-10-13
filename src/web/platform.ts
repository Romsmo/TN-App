/** What the page can tell about how it is running. Pure functions of their input, so they are testable without a browser. */

export type Os = 'ios' | 'android' | 'other';

export function detectOs(userAgent: string, maxTouchPoints = 0, platform = ''): Os {
  if (/iPhone|iPad|iPod/.test(userAgent)) return 'ios';
  // iPadOS 13+ presents itself as a Mac with a touch screen
  if (platform === 'MacIntel' && maxTouchPoints > 1) return 'ios';
  if (/Android/.test(userAgent)) return 'android';
  return 'other';
}

/** True when the page runs as an installed app: no browser bar (display mode standalone or fullscreen, or iOS' own flag). */
export function isStandalone(env: { matchMedia?: (query: string) => { matches: boolean }; navigatorStandalone?: boolean }): boolean {
  if (env.navigatorStandalone === true) return true;
  const match = (query: string) => env.matchMedia?.(query).matches === true;
  return match('(display-mode: standalone)') || match('(display-mode: fullscreen)') || match('(display-mode: minimal-ui)');
}

/** Whether to point out the installation: a phone or tablet, in a browser tab, and not dismissed before. */
export function shouldOfferInstall(input: { os: Os; standalone: boolean; dismissed: boolean }): boolean {
  return input.os !== 'other' && !input.standalone && !input.dismissed;
}
