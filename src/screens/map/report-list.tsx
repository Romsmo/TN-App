import { Pressable, StyleSheet, Text, View } from 'react-native';

import { MIN_TOUCH } from '@/components/ui';
import { t } from '@/i18n';
import { hazardLabel } from '@/map/hazard-labels';
import type { HazardItem } from '@/tn/types';
import { useTheme } from '@/theme';

type Props = { items: readonly HazardItem[]; onSelect: (id: string) => void };

/**
 * The reports of the current map area as a plain list, nearest first. A map is not usable with a screen reader, the list is:
 * every row says what, how far and how well confirmed.
 */
export function ReportList({ items, onSelect }: Props) {
  const theme = useTheme();
  const sorted = [...items].sort((a, b) => a.distanceMeters - b.distanceMeters);
  if (sorted.length === 0) return <Text style={[styles.empty, { color: theme.textSecondary }]}>{t('map.listEmpty')}</Text>;
  return (
    <View accessibilityRole="list" style={styles.list}>
      {sorted.map((item) => {
        const meters = Math.round(item.distanceMeters);
        return (
          <Pressable
            key={item.id}
            accessibilityRole="button"
            accessibilityLabel={t('map.listRow', { type: hazardLabel(item.hazardType), meters, count: item.confirmCount })}
            onPress={() => onSelect(item.id)}
            style={[styles.row, { backgroundColor: theme.surface }]}>
            <Text style={[styles.type, { color: theme.text }]}>{hazardLabel(item.hazardType)}</Text>
            <Text style={[styles.sub, { color: theme.textSecondary }]}>{t('detail.distance', { meters })}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  list: { gap: 8, padding: 12 },
  empty: { padding: 16, fontSize: 16 },
  row: { minHeight: MIN_TOUCH, borderRadius: 12, paddingHorizontal: 14, paddingVertical: 8, justifyContent: 'center' },
  type: { fontSize: 17, fontWeight: '600' },
  sub: { fontSize: 14 },
});
