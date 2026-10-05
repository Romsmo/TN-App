import { Pressable, StyleSheet, Text, View } from 'react-native';

import { MIN_TOUCH } from '@/components/ui';
import { formatDateTime } from '@/i18n/format';
import { t } from '@/i18n';
import { hazardLabel } from '@/map/hazard-labels';
import type { HazardItem } from '@/tn/types';
import { useTheme } from '@/theme';

type Props = { item: HazardItem; onClose: () => void };

/** Details of one report: kind, how sure the community is, how long it stays. */
export function DetailCard({ item, onClose }: Props) {
  const theme = useTheme();
  return (
    <View accessibilityViewIsModal style={[styles.card, { backgroundColor: theme.surface }]}>
      <View style={styles.header}>
        <Text accessibilityRole="header" style={[styles.title, { color: theme.text }]}>
          {hazardLabel(item.hazardType)}
        </Text>
        <Pressable accessibilityRole="button" accessibilityLabel={t('detail.close')} onPress={onClose} style={styles.close}>
          <Text style={[styles.closeText, { color: theme.tint }]}>{t('detail.close')}</Text>
        </Pressable>
      </View>
      <Text style={[styles.line, { color: theme.text }]}>
        {t('detail.confirmed', { count: item.confirmCount })} · {t('detail.denied', { count: item.denyCount })}
      </Text>
      <Text style={[styles.line, { color: theme.textSecondary }]}>{t('detail.validUntil', { time: formatDateTime(item.expiresAt) })}</Text>
      <Text style={[styles.line, { color: theme.textSecondary }]}>{t('detail.distance', { meters: Math.round(item.distanceMeters) })}</Text>
      {item.pending ? <Text style={[styles.line, { color: theme.textSecondary }]}>{t('detail.pending')}</Text> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  card: { borderRadius: 14, padding: 14, gap: 4 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  title: { fontSize: 20, fontWeight: '600', flexShrink: 1 },
  close: { minHeight: MIN_TOUCH, minWidth: MIN_TOUCH, alignItems: 'center', justifyContent: 'center' },
  closeText: { fontSize: 16, fontWeight: '600' },
  line: { fontSize: 15 },
});
