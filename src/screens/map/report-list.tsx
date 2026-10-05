import { Pressable, StyleSheet, Text, View } from 'react-native';

import { Icon } from '@/components/icon';
import { MIN_TOUCH } from '@/components/ui';
import { t } from '@/i18n';
import { hazardColor } from '@/map/colors';
import { hazardIcon } from '@/map/hazard-icons';
import { hazardLabel } from '@/map/hazard-labels';
import { pointType, type PointItem } from '@/map/geojson';
import { elevation, radius, type, useTheme } from '@/theme';

type Props = { items: readonly PointItem[]; onSelect: (id: string) => void };

/**
 * The reports of the current map area as a plain list, nearest first. A map is not usable with a screen reader, the list is:
 * every row says what, how far and how well confirmed.
 */
export function ReportList({ items, onSelect }: Props) {
  const theme = useTheme();
  const sorted = [...items].sort((a, b) => a.distanceMeters - b.distanceMeters);
  if (sorted.length === 0) return <Text style={[type.body, styles.empty, { color: theme.textSecondary }]}>{t('map.listEmpty')}</Text>;
  return (
    <View accessibilityRole="list" style={styles.list}>
      {sorted.map((item) => {
        const meters = Math.round(item.distanceMeters);
        const kind = pointType(item);
        return (
          <Pressable
            key={item.id}
            accessibilityRole="button"
            accessibilityLabel={item.kind === 'hazard' ? t('map.listRow', { type: hazardLabel(kind), meters, count: item.confirmCount }) : t('map.listRowCamera', { type: hazardLabel(kind), meters })}
            onPress={() => onSelect(item.id)}
            style={[styles.row, elevation(theme), { backgroundColor: theme.surface }]}>
            <View style={[styles.badge, { backgroundColor: hazardColor(kind) }]}>
              <Icon name={hazardIcon(kind)} size={20} color="#FFFFFF" />
            </View>
            <View style={styles.text}>
              <Text style={[styles.type, { color: theme.text }]}>{hazardLabel(kind)}</Text>
              <Text style={[type.caption, { color: theme.textSecondary }]}>{t('detail.distance', { meters })}</Text>
            </View>
            <Icon name="chevron-forward" size={20} color={theme.textSecondary} />
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  list: { gap: 10, padding: 16 },
  empty: { padding: 16 },
  row: { minHeight: MIN_TOUCH + 8, borderRadius: radius.md, paddingHorizontal: 14, paddingVertical: 10, flexDirection: 'row', alignItems: 'center', gap: 12 },
  badge: { width: 40, height: 40, borderRadius: 20, alignItems: 'center', justifyContent: 'center' },
  text: { flex: 1 },
  type: { fontSize: 17, fontWeight: '700' },
});
