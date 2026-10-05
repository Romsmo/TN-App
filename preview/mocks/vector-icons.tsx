import { useEffect } from 'react';
import { Text } from 'react-native';

import { GLYPHS, IONICONS_TTF_BASE64 } from './ionicons-font';

let injected = false;
function injectFont() {
  if (injected || typeof document === 'undefined') return;
  injected = true;
  const style = document.createElement('style');
  style.textContent = `@font-face{font-family:"IoniconsInline";src:url(data:font/ttf;base64,${IONICONS_TTF_BASE64}) format("truetype");font-display:block}`;
  document.head.appendChild(style);
}

/** Ionicons for the browser preview: the real font, embedded, so the picture shows the real symbols. */
export function Ionicons({ name, size = 22, color = '#000' }: { name: string; size?: number; color?: string }) {
  useEffect(injectFont, []);
  injectFont();
  const code = GLYPHS[name];
  return <Text style={{ fontFamily: 'IoniconsInline', fontSize: size, color, lineHeight: size + 2 }}>{code ? String.fromCodePoint(code) : '?'}</Text>;
}
