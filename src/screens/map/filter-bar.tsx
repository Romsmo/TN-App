import { Pressable, ScrollView, StyleSheet, Text } from 'react-native';

import { MIN_TOUCH } from '@/components/ui';
import { t } from '@/i18n';
import { hazardLabel } from '@/map/hazard-labels';
import { useTheme } from '@/theme';

type Props = {
  /** Types present in the data (from the library, not hard-wired). */
  types: readonly string[];
  hidden: readonly string[];
  onToggle: (type: string) => void;
};

export function FilterBar({ types, hidden, onToggle }: Props) {
  const theme = useTheme();
  if (types.length === 0) return null;
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.scroll} contentContainerStyle={styles.row} accessibilityLabel={t('map.filter.title')}>
      {types.map((type) => {
        const on = !hidden.includes(type);
        return (
          <Pressable
            key={type}
            accessibilityRole="switch"
            accessibilityLabel={t('map.filter.toggle', { type: hazardLabel(type) })}
            accessibilityState={{ checked: on }}
            onPress={() => onToggle(type)}
            style={[styles.chip, { backgroundColor: on ? theme.tint : theme.surface }]}>
            <Text style={{ color: on ? theme.onTint : theme.text, fontSize: 15, fontWeight: '600' }}>{hazardLabel(type)}</Text>
          </Pressable>
        );
      })}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  // a horizontal ScrollView grows to fill a column by default; the filter bar must only be as tall as its chips
  scroll: { flexGrow: 0 },
  row: { gap: 8, paddingHorizontal: 12, paddingVertical: 8 },
  chip: { minHeight: MIN_TOUCH - 8, paddingHorizontal: 14, borderRadius: 20, alignItems: 'center', justifyContent: 'center' },
});
