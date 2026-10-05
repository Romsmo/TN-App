import { useColorScheme } from 'react-native';

export const colors = {
  light: { text: '#11181C', textSecondary: '#5B6670', background: '#FFFFFF', surface: '#F1F3F5', tint: '#0A6EBD', onTint: '#FFFFFF', danger: '#B3261E' },
  dark: { text: '#ECEDEE', textSecondary: '#9BA3AB', background: '#101214', surface: '#1B1E21', tint: '#5BB0F0', onTint: '#0B1620', danger: '#F2B8B5' },
} as const;

export type Theme = (typeof colors)[keyof typeof colors];

export function useTheme(): Theme {
  return useColorScheme() === 'dark' ? colors.dark : colors.light;
}
