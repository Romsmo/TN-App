import { ScrollView, StyleSheet, Text, View } from 'react-native';

import { Icon } from '@/components/icon';
import { useLockActive } from '@/drive/drive-provider';
import { t } from '@/i18n';
import { TAB_BAR_CLEARANCE, type, useTheme } from '@/theme';

/** Shows its content only when the speed lock is not in force; otherwise a short explanation instead. */
export function LockGuard({ children }: { children: React.ReactNode }) {
  const locked = useLockActive();
  const theme = useTheme();
  if (!locked) return <>{children}</>;
  return (
    <ScrollView style={{ backgroundColor: theme.background }} contentContainerStyle={styles.content}>
      <View accessibilityRole="alert" style={styles.box}>
        <Icon name="lock-closed" size={36} color={theme.tint} />
        <Text accessibilityRole="header" style={[type.title, { color: theme.text }]}>
          {t('lock.title')}
        </Text>
        <Text style={[type.body, { color: theme.textSecondary }]}>{t('lock.body')}</Text>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  content: { flexGrow: 1, justifyContent: 'center', padding: 24, paddingBottom: TAB_BAR_CLEARANCE + 16 },
  box: { gap: 12 },
});
