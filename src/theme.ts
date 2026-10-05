import { Platform, useColorScheme, type ViewStyle } from 'react-native';

/**
 * Design tokens, following Apple's design language: grouped backgrounds (#F2F2F7 / true black), white or elevated-grey
 * grouped surfaces, hairline separators, one system blue for actions, status colours only for status. The dark scheme
 * follows the system setting. Contrast is checked in theme-contrast.test.ts.
 */
export const colors = {
  light: {
    text: '#0A0A0C',
    textSecondary: '#6C6C70',
    background: '#F2F2F7',
    surface: '#FFFFFF',
    surfaceAlt: '#E9E9EE',
    border: '#D1D1D6',
    tint: '#0062E0',
    tintSoft: '#E3EEFF',
    onTint: '#FFFFFF',
    danger: '#D70015',
    warn: '#B25000',
    success: '#1E7B34',
    overlay: 'rgba(0, 0, 0, 0.4)',
    shadow: '#000000',
  },
  dark: {
    text: '#FFFFFF',
    textSecondary: '#A1A1A6',
    background: '#000000',
    surface: '#1C1C1E',
    surfaceAlt: '#2C2C2E',
    border: '#38383A',
    tint: '#4DA3FF',
    tintSoft: '#10294A',
    onTint: '#001A38',
    danger: '#FF6961',
    warn: '#FF9F0A',
    success: '#30D158',
    overlay: 'rgba(0, 0, 0, 0.6)',
    shadow: '#000000',
  },
} as const;

export type Theme = (typeof colors)[keyof typeof colors];

export function useTheme(): Theme {
  return useColorScheme() === 'dark' ? colors.dark : colors.light;
}

/** iOS "continuous" (squircle) corners; ignored elsewhere. Spread into any rounded surface. */
export const squircle = { borderCurve: 'continuous' } as const;

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
