import { Platform, useColorScheme, type ViewStyle } from 'react-native';

/**
 * Design tokens. A calm, light-and-airy look: soft grounded surfaces, white cards with big radii and gentle shadows,
 * one confident blue for actions, status colours only for status. Dark mode keeps the same structure on a deep navy.
 */
export const colors = {
  light: {
    text: '#0E1A27',
    textSecondary: '#566474',
    background: '#F2F5F9',
    surface: '#FFFFFF',
    surfaceAlt: '#E8EEF5',
    border: '#DCE3EC',
    tint: '#1D4ED8',
    tintSoft: '#E4ECFF',
    onTint: '#FFFFFF',
    danger: '#C62828',
    warn: '#B45309',
    success: '#15803D',
    overlay: 'rgba(14, 26, 39, 0.45)',
    shadow: '#0E1A27',
  },
  dark: {
    text: '#EAF0F7',
    textSecondary: '#9FB0C2',
    background: '#0A121C',
    surface: '#121D2A',
    surfaceAlt: '#1A2A3B',
    border: '#223244',
    tint: '#6AA3FF',
    tintSoft: '#182A4D',
    onTint: '#06142B',
    danger: '#FF8A80',
    warn: '#F6B25C',
    success: '#6EE7A0',
    overlay: 'rgba(0, 0, 0, 0.6)',
    shadow: '#000000',
  },
} as const;

export type Theme = (typeof colors)[keyof typeof colors];

export function useTheme(): Theme {
  return useColorScheme() === 'dark' ? colors.dark : colors.light;
}

/** Corner radii. Big on purpose: cards 24, sheets 28, pills fully round. */
export const radius = { sm: 12, md: 18, lg: 24, sheet: 28, pill: 999 } as const;

export const space = { xs: 4, sm: 8, md: 12, lg: 16, xl: 24 } as const;

/** Type scale: a strong title, a clear section label, readable body, quiet caption. */
export const type = {
  title: { fontSize: 30, fontWeight: '800', letterSpacing: -0.6 },
  heading: { fontSize: 20, fontWeight: '700', letterSpacing: -0.2 },
  body: { fontSize: 16, lineHeight: 22 },
  label: { fontSize: 12, fontWeight: '700', letterSpacing: 0.8, textTransform: 'uppercase' },
  caption: { fontSize: 13, lineHeight: 18 },
} as const;

/** A soft lift for cards, sheets and floating controls. */
export function elevation(theme: Theme, level: 1 | 2 = 1): ViewStyle {
  const strength = level === 2 ? 0.2 : 0.1;
  return Platform.select<ViewStyle>({
    ios: { shadowColor: theme.shadow, shadowOpacity: strength, shadowRadius: level === 2 ? 22 : 12, shadowOffset: { width: 0, height: level === 2 ? 10 : 4 } },
    android: { elevation: level === 2 ? 10 : 3 },
    default: { boxShadow: `0 ${level === 2 ? 10 : 4}px ${level === 2 ? 28 : 14}px rgba(14, 26, 39, ${strength})` } as ViewStyle,
  }) as ViewStyle;
}

/** Room at the bottom of a screen for the floating tab bar. */
export const TAB_BAR_CLEARANCE = 96;
