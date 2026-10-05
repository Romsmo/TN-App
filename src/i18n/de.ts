/** Alle sichtbaren Texte der App, Deutsch. Neue Schlüssel zuerst hier, dann in en.ts (der Typ erzwingt es). */
export const de = {
  'app.name': 'TNViewer',
  'tabs.map': 'Karte',
  'tabs.drive': 'Fahrmodus',
  'tabs.settings': 'Einstellungen',
  'placeholder.title': 'Noch nicht umgesetzt',
  'placeholder.body': 'Dieser Bereich wird in einer späteren Stufe gebaut.',
  'settings.version': 'Version {version}',
} as const;

export type TextKey = keyof typeof de;
