/** Drive-mode colours: dark, low glare, high contrast for the few things that matter. Not the app theme. */
export const drivePalette = {
  background: '#0B0D10',
  surface: '#161A1F',
  text: '#E8EAED',
  textSecondary: '#A3AAB2',
  /** Speed within the limit. */
  ok: '#E8EAED',
  /** Speed over the limit. */
  over: '#FF7A70',
  warnFirst: '#E8A93A',
  warnSecond: '#FF7A70',
  tint: '#5BB0F0',
  onTint: '#08141F',
  badge: '#7A3B35',
  /** Raised tiles for the report buttons. */
  tile: '#1B2430',
  /** The speed-limit sign: dimmed white (no glare at night), red ring, black figures. */
  sign: '#E9EBEE',
  signRing: '#D32F2F',
  signInk: '#0B0D10',
  /** Text on the amber and red warning cards. */
  onWarn: '#0B0D10',
} as const;
