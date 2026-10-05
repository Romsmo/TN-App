import { Pressable, StyleSheet, Text, View } from 'react-native';

import { Button, MIN_TOUCH } from '@/components/ui';
import { t } from '@/i18n';
import { hazardLabel } from '@/map/hazard-labels';
import type { Position } from '@/report/submit';
import { useTheme } from '@/theme';

export type ReportLocation = (Position & { source: 'device' | 'map' }) | null;

type Props = {
  types: readonly string[];
  location: ReportLocation;
  /** The device position is still being determined (and no spot was tapped). */
  locating: boolean;
  /** A message about the last attempt, e.g. an error; null = none. */
  message: string | null;
  onPick: (type: string) => void;
  onCancel: () => void;
};

/** The "report" panel over the map: where, and one big button per type. */
export function ReportSheet({ types, location, locating, message, onPick, onCancel }: Props) {
  const theme = useTheme();
  const where = location ? (location.source === 'map' ? t('report.atMap') : t('report.atDevice')) : locating ? t('report.locating') : t('report.noLocation');
  return (
    <View accessibilityViewIsModal style={[styles.sheet, { backgroundColor: theme.surface }]}>
      <Text accessibilityRole="header" style={[styles.title, { color: theme.text }]}>
        {t('report.title')}
      </Text>
      <Text style={[styles.where, { color: theme.textSecondary }]}>{where}</Text>
      <Text style={[styles.where, { color: theme.textSecondary }]}>{t('report.hint')}</Text>
      <View style={styles.grid}>
        {types.map((type) => (
          <Pressable
            key={type}
            accessibilityRole="button"
            accessibilityLabel={t('report.type', { type: hazardLabel(type) })}
            accessibilityState={{ disabled: !location }}
            disabled={!location}
            onPress={() => onPick(type)}
            style={({ pressed }) => [styles.tile, { backgroundColor: theme.tint, opacity: !location ? 0.4 : pressed ? 0.8 : 1 }]}>
            <Text style={[styles.tileText, { color: theme.onTint }]}>{hazardLabel(type)}</Text>
          </Pressable>
        ))}
      </View>
      {message ? (
        <Text accessibilityRole="alert" style={[styles.where, { color: theme.text }]}>
          {message}
        </Text>
      ) : null}
      <Button kind="plain" label={t('report.cancel')} onPress={onCancel} />
    </View>
  );
}

const styles = StyleSheet.create({
  sheet: { borderRadius: 16, padding: 14, gap: 8 },
  title: { fontSize: 20, fontWeight: '600' },
  where: { fontSize: 15 },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  tile: { flexGrow: 1, flexBasis: '45%', minHeight: MIN_TOUCH + 16, borderRadius: 12, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 8 },
  tileText: { fontSize: 18, fontWeight: '700', textAlign: 'center' },
});
