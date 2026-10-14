import { detectOs, isStandalone, shouldOfferInstall } from './platform';

describe('detectOs', () => {
  it('knows an iPhone, an iPad that says it is a Mac, and Android', () => {
    expect(detectOs('Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15')).toBe('ios');
    expect(detectOs('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)', 5, 'MacIntel')).toBe('ios');
    expect(detectOs('Mozilla/5.0 (Linux; Android 14; Pixel 8) Chrome/126 Mobile')).toBe('android');
  });
  it('treats a desktop Mac as other', () => {
    expect(detectOs('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)', 0, 'MacIntel')).toBe('other');
    expect(detectOs('Mozilla/5.0 (X11; Linux x86_64)')).toBe('other');
  });
});

describe('isStandalone', () => {
  const media = (...on: string[]) => (query: string) => ({ matches: on.includes(query) });
  it('is true for the display modes without a browser bar and for iOS\' own flag', () => {
    expect(isStandalone({ matchMedia: media('(display-mode: standalone)') })).toBe(true);
    expect(isStandalone({ matchMedia: media('(display-mode: fullscreen)') })).toBe(true);
    expect(isStandalone({ navigatorStandalone: true })).toBe(true);
  });
  it('is false in a normal tab, and when nothing can be asked', () => {
    expect(isStandalone({ matchMedia: media('(display-mode: browser)') })).toBe(false);
    expect(isStandalone({})).toBe(false);
  });
});

describe('shouldOfferInstall', () => {
  it('offers it on a phone in a browser tab, until dismissed', () => {
    expect(shouldOfferInstall({ os: 'ios', standalone: false, dismissed: false })).toBe(true);
    expect(shouldOfferInstall({ os: 'android', standalone: false, dismissed: true })).toBe(false);
  });
  it('does not offer it when already installed or on a desktop', () => {
    expect(shouldOfferInstall({ os: 'ios', standalone: true, dismissed: false })).toBe(false);
    expect(shouldOfferInstall({ os: 'other', standalone: false, dismissed: false })).toBe(false);
  });
});
