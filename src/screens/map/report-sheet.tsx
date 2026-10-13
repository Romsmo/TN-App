import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, TextInput, useWindowDimensions, View } from 'react-native';

import { Icon } from '@/components/icon';
import { Button, MIN_TOUCH } from '@/components/ui';
import { t } from '@/i18n';
import { isCameraType } from '@/map/camera-types';
import { hazardColor } from '@/map/colors';
import { hazardIcon } from '@/map/hazard-icons';
import { hazardLabel } from '@/map/hazard-labels';
import { DEFAULT_CHOICE, formatDuration, parseDuration, QUICK_SECONDS, type DurationChoice, type DurationUnit } from '@/report/duration';
import type { Position } from '@/report/submit';
import { elevation, radius, squircle, type, useTheme } from '@/theme';

export type ReportLocation = (Position & { source: 'device' | 'map' }) | null;

type Props = {
  types: readonly string[];
  location: ReportLocation;
  /** The device position is still being determined (and no spot was tapped). */
  locating: boolean;
  /** A message about the last attempt, e.g. an error; null = none. */
  message: string | null;
  onPick: (type: string, choice: DurationChoice) => void;
  onCancel: () => void;
};

function TypeTile({ type: reportType, enabled, onPick }: { type: string; enabled: boolean; onPick: (type: string) => void }) {
  const theme = useTheme();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={t('report.type', { type: hazardLabel(reportType) })}
      accessibilityState={{ disabled: !enabled }}
      disabled={!enabled}
      onPress={() => onPick(reportType)}
      style={({ pressed }) => [styles.tile, { backgroundColor: theme.surfaceAlt, opacity: !enabled ? 0.4 : pressed ? 0.8 : 1 }]}>
      <View style={[styles.tileIcon, { backgroundColor: hazardColor(reportType) }]}>
        <Icon name={hazardIcon(reportType)} size={24} color="#FFFFFF" />
      </View>
      <Text style={[styles.tileText, { color: theme.text }]}>{hazardLabel(reportType)}</Text>
    </Pressable>
  );
}

const UNITS: DurationUnit[] = ['min', 'h', 'd'];

function Chip({ label, selected, onPress }: { label: string; selected: boolean; onPress: () => void }) {
  const theme = useTheme();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ selected }}
      onPress={onPress}
      style={[styles.chip, { backgroundColor: selected ? theme.tint : theme.surfaceAlt }]}>
      <Text style={[type.caption, { color: selected ? theme.onTint : theme.text, fontWeight: '600' }]}>{label}</Text>
    </Pressable>
  );
}

/** "How long should it stay?" – "Standard" (the server's own duration for the type) is preselected. */
function DurationPicker({ choice, onChoice }: { choice: DurationChoice; onChoice: (choice: DurationChoice) => void }) {
  const theme = useTheme();
  const [amount, setAmount] = useState('');
  const [unit, setUnit] = useState<DurationUnit>('h');
  const custom = choice.kind === 'custom';
  const typed = (nextAmount: string, nextUnit: DurationUnit) => {
    setAmount(nextAmount);
    setUnit(nextUnit);
    const seconds = parseDuration(nextAmount, nextUnit);
    onChoice(seconds ? { kind: 'custom', seconds } : { kind: 'custom', seconds: 0 });
  };
  return (
    <View style={styles.durationBox}>
      <Text accessibilityRole="header" style={[type.label, { color: theme.textSecondary }]}>
        {t('report.duration')}
      </Text>
      <View style={styles.chips}>
        <Chip label={t('report.duration.default')} selected={!custom} onPress={() => onChoice(DEFAULT_CHOICE)} />
        <Chip label={t('report.duration.custom')} selected={custom} onPress={() => onChoice({ kind: 'custom', seconds: QUICK_SECONDS[1] })} />
      </View>
      {custom ? (
        <>
          <View style={styles.chips}>
            {QUICK_SECONDS.map((seconds) => (
              <Chip key={seconds} label={formatDuration(seconds)} selected={choice.seconds === seconds} onPress={() => onChoice({ kind: 'custom', seconds })} />
            ))}
          </View>
          <View style={styles.inputRow}>
            <TextInput
              accessibilityLabel={t('report.duration.input')}
              keyboardType="decimal-pad"
              inputMode="decimal"
              value={amount}
              onChangeText={(text) => typed(text, unit)}
              placeholder={t('report.duration.input')}
              placeholderTextColor={theme.textSecondary}
              style={[styles.input, { color: theme.text, backgroundColor: theme.surfaceAlt, borderColor: theme.border }]}
            />
            {UNITS.map((u) => (
              <Chip key={u} label={t(`report.duration.unit.${u}`)} selected={unit === u} onPress={() => typed(amount, u)} />
            ))}
          </View>
          <Text style={[type.caption, { color: theme.textSecondary }]}>{t('report.duration.hint')}</Text>
        </>
      ) : null}
    </View>
  );
}

/** The "report" bottom sheet over the map: where, and one big tile per type. */
export function ReportSheet({ types, location, locating, message, onPick, onCancel }: Props) {
  const theme = useTheme();
  const { height } = useWindowDimensions();
  const [choice, setChoice] = useState<DurationChoice>(DEFAULT_CHOICE);
  const invalidCustom = choice.kind === 'custom' && choice.seconds <= 0;
  const pick = (reportType: string) => onPick(reportType, choice);
  const plain = types.filter((reportType) => !isCameraType(reportType));
  const cameras = types.filter(isCameraType);
  const where = location ? (location.source === 'map' ? t('report.atMap') : t('report.atDevice')) : locating ? t('report.locating') : t('report.noLocation');
  return (
    <View accessibilityViewIsModal style={[styles.sheet, squircle, elevation(theme, 2), { backgroundColor: theme.surface }]}>
      <View style={[styles.grabber, { backgroundColor: theme.border }]} />
      <Text accessibilityRole="header" style={[type.heading, { color: theme.text }]}>
        {t('report.title')}
      </Text>
      <View style={styles.whereRow}>
        <Icon name={location?.source === 'map' ? 'pin' : 'locate'} size={16} color={theme.tint} />
        <Text style={[type.caption, { color: theme.textSecondary, flex: 1 }]}>{where}</Text>
      </View>
      <Text style={[type.caption, { color: theme.textSecondary }]}>{t('report.hint')}</Text>
      <DurationPicker choice={choice} onChoice={setChoice} />
      <ScrollView style={{ maxHeight: height * 0.5 }} contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>
        <View style={styles.grid}>
          {plain.map((reportType) => (
            <TypeTile key={reportType} type={reportType} enabled={!!location && !invalidCustom} onPick={pick} />
          ))}
        </View>
        {cameras.length > 0 ? (
          <>
            <Text accessibilityRole="header" style={[type.label, { color: theme.textSecondary }]}>
              {t('hazard.cameras')}
            </Text>
            <View style={styles.grid}>
              {cameras.map((reportType) => (
                <TypeTile key={reportType} type={reportType} enabled={!!location && !invalidCustom} onPick={pick} />
              ))}
            </View>
          </>
        ) : null}
      </ScrollView>
      {message ? (
        <Text accessibilityRole="alert" style={[type.body, { color: theme.text }]}>
          {message}
        </Text>
      ) : null}
      <Button kind="plain" label={t('report.cancel')} onPress={onCancel} />
    </View>
  );
}

const styles = StyleSheet.create({
  sheet: { borderRadius: radius.sheet, padding: 18, paddingTop: 10, gap: 8 },
  grabber: { alignSelf: 'center', width: 40, height: 5, borderRadius: 3, marginBottom: 6 },
  whereRow: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  scroll: { gap: 8 },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 10, marginVertical: 4 },
  durationBox: { gap: 6 },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, alignItems: 'center' },
  chip: { minHeight: MIN_TOUCH - 4, paddingHorizontal: 14, borderRadius: radius.md, alignItems: 'center', justifyContent: 'center' },
  inputRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, alignItems: 'center' },
  input: { minWidth: 90, minHeight: MIN_TOUCH - 4, borderRadius: radius.md, borderWidth: StyleSheet.hairlineWidth, paddingHorizontal: 12, fontSize: 16 },
  tile: { flexGrow: 1, flexBasis: '30%', minHeight: MIN_TOUCH + 44, borderRadius: radius.md, alignItems: 'center', justifyContent: 'center', gap: 8, paddingVertical: 12, paddingHorizontal: 6 },
  tileIcon: { width: 44, height: 44, borderRadius: 22, alignItems: 'center', justifyContent: 'center' },
  tileText: { fontSize: 15, fontWeight: '700', textAlign: 'center' },
});
