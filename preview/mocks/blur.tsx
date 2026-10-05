import type { CSSProperties } from 'react';
import { View, type ViewProps } from 'react-native';

/** expo-blur for the browser preview: a translucent layer with a CSS backdrop blur, tinted like the system materials. */
export function BlurView({ tint = 'default', intensity = 50, style, ...rest }: ViewProps & { tint?: string; intensity?: number }) {
  const dark = /Dark|dark/.test(tint);
  const web = { backdropFilter: `blur(${Math.round(intensity / 4)}px) saturate(1.8)`, WebkitBackdropFilter: `blur(${Math.round(intensity / 4)}px) saturate(1.8)` } as CSSProperties;
  return <View {...rest} style={[style, web as object, { backgroundColor: dark ? 'rgba(28,28,30,0.88)' : 'rgba(255,255,255,0.88)' }]} />;
}
