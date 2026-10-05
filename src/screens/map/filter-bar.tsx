import { Pressable, ScrollView, StyleSheet, Text } from 'react-native';

import { Icon } from '@/components/icon';
import { MIN_TOUCH } from '@/components/ui';
import { t } from '@/i18n';
import { hazardColor } from '@/map/colors';
import { hazardIcon } from '@/map/hazard-icons';
import { hazardLabel } from '@/map/hazard-labels';
import { elevation, radius, useTheme } from '@/theme';

type Props = {
  /** Types present in the data (from the library, not hard-wired). */
  types: readonly string[];
  hidden: readonly string[];
  onToggle: (type: string) => void;
};

/** Filter chips: white with the category colour when the type is shown, muted with a crossed-out eye when hidden. */
export function FilterBar({ types, hidden, onToggle }: Props) {
  const theme = useTheme();
  if (types.length === 0) return null;
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.scroll} contentContainerStyle={styles.row} accessibilityLabel={t('map.filter.title')}>
      {types.map((type) => {
        const on = !hidden.includes(type);
        const foreground = on ? theme.text : theme.textSecondary;
        return (
          <Pressable
            key={type}
            accessibilityRole="switch"
            accessibilityLabel={t('map.filter.toggle', { type: hazardLabel(type) })}
            accessibilityState={{ checked: on }}
            onPress={() => onToggle(type)}
            style={[styles.chip, on ? elevation(theme) : null, { backgroundColor: on ? theme.surface : theme.surfaceAlt, opacity: on ? 1 : 0.85 }]}>
            <Icon name={on ? hazardIcon(type) : 'eye-off-outline'} size={16} color={on ? hazardColor(type) : foreground} />
            <Text style={[styles.chipText, { color: foreground }]}>{hazardLabel(type)}</Text>
          </Pressable>
        );
      })}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  // a horizontal ScrollView grows to fill a column by default; the filter bar must only be as tall as its chips
  scroll: { flexGrow: 0 },
  row: { gap: 8, paddingHorizontal: 16, paddingVertical: 6 },
  chip: { minHeight: MIN_TOUCH - 10, paddingHorizontal: 14, borderRadius: radius.pill, flexDirection: 'row', alignItems: 'center', gap: 6 },
  chipText: { fontSize: 15, fontWeight: '700' },
});
