/** Drive-mode colours: dark, low glare, high contrast for the few things that matter. Not the app theme. */
export const drivePalette = {
  background: '#0B0D10',
  surface: '#161A1F',
  text: '#E8EAED',
  textSecondary: '#A3AAB2',
  /** Speed within the limit. */
  ok: '#E8EAED',
  /** Speed over the limit. */
  over: '#FF6B5E',
  warnFirst: '#E8A93A',
  warnSecond: '#FF6B5E',
  tint: '#5BB0F0',
  onTint: '#08141F',
  badge: '#7A3B35',
} as const;
