import { StyleSheet, Text, View } from 'react-native';

import { t } from '@/i18n';
import { type, useTheme } from '@/theme';

type Props = { title: string; children?: React.ReactNode };

/** Stand-in for areas that a later stage builds; says so instead of pretending. */
export function Placeholder({ title, children }: Props) {
  const theme = useTheme();
  return (
    <View style={[styles.screen, { backgroundColor: theme.background }]}>
      <Text accessibilityRole="header" style={[type.heading, { color: theme.text }]}>
        {title}
      </Text>
      <Text style={[type.body, { color: theme.textSecondary, textAlign: 'center' }]}>{t('placeholder.body')}</Text>
      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24, gap: 8 },
});
