import { ScrollView, StyleSheet, Text, View } from 'react-native';

import { useLockActive } from '@/drive/drive-provider';
import { t } from '@/i18n';
import { useTheme } from '@/theme';

/** Shows its content only when the speed lock is not in force; otherwise a short explanation instead. */
export function LockGuard({ children }: { children: React.ReactNode }) {
  const locked = useLockActive();
  const theme = useTheme();
  if (!locked) return <>{children}</>;
  return (
    <ScrollView style={{ backgroundColor: theme.background }} contentContainerStyle={styles.content}>
      <View accessibilityRole="alert" style={styles.box}>
        <Text accessibilityRole="header" style={[styles.title, { color: theme.text }]}>
          {t('lock.title')}
        </Text>
        <Text style={[styles.body, { color: theme.textSecondary }]}>{t('lock.body')}</Text>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  content: { flexGrow: 1, justifyContent: 'center', padding: 24 },
  box: { gap: 12 },
  title: { fontSize: 24, fontWeight: '700' },
  body: { fontSize: 17, lineHeight: 24 },
});
