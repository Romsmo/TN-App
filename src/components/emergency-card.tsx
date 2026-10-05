import { useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { Icon } from '@/components/icon';
import { Button } from '@/components/ui';
import { t } from '@/i18n';
import type { Emergency } from '@/state/connection';
import { elevation, radius, squircle, type, useTheme } from '@/theme';

type Props = {
  reason: Emergency;
  /** Tries to reach a server now (an explicit tap goes on mobile data too). */
  onRetry: () => Promise<void>;
  /** Opens "Server verbinden". */
  onSetup: () => void;
};

/**
 * The emergency mode as the user sees it: what is missing, what still works, and the two things they can do about it.
 * It is a card on the map, not a dead end: the map, reporting and the drive mode stay usable.
 */
export function EmergencyCard({ reason, onRetry, onSetup }: Props) {
  const theme = useTheme();
  const [busy, setBusy] = useState(false);
  const retry = () => {
    setBusy(true);
    onRetry().finally(() => setBusy(false));
  };
  return (
    <View accessibilityRole="alert" style={[styles.card, squircle, elevation(theme, 2), { backgroundColor: theme.surface }]}>
      <View style={styles.header}>
        <View style={[styles.badge, squircle, { backgroundColor: theme.warn }]}>
          <Icon name="cloud-offline" size={20} color="#FFFFFF" />
        </View>
        <Text accessibilityRole="header" style={[type.heading, { color: theme.text }]}>
          {t('emergency.title')}
        </Text>
      </View>
      <Text style={[type.caption, { color: theme.textSecondary }]}>{t(reason === 'noAccess' ? 'emergency.noAccess' : 'emergency.noServer')}</Text>
      <Text style={[type.caption, { color: theme.textSecondary }]}>{t('emergency.auto')}</Text>
      <View style={styles.buttons}>
        <Button label={busy ? t('emergency.retrying') : t('emergency.retry')} icon="refresh" disabled={busy} onPress={retry} />
        <Button kind="plain" label={t('emergency.setup')} icon="server" onPress={onSetup} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: { marginHorizontal: 16, borderRadius: radius.lg, padding: 16, gap: 8 },
  header: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  badge: { width: 32, height: 32, borderRadius: 9, alignItems: 'center', justifyContent: 'center' },
  buttons: { gap: 8, marginTop: 4 },
});
