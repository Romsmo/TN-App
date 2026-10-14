import { useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text, TextInput, View } from 'react-native';

import { Icon } from '@/components/icon';
import { Button, MIN_TOUCH } from '@/components/ui';
import { t } from '@/i18n';
import { lookupSpot, parseLimitValue, proposeCorrection, proposeMissing, QUICK_LIMITS, WRONG_REASONS, type LookupState, type WrongReason, type ProposalOutcome, type Spot } from '@/limits/speed-limit';
import type { TnService } from '@/tn/service';
import type { SpeedLimitLookup, SpeedUnit } from '@/tn/types';
import { elevation, radius, squircle, type, useTheme } from '@/theme';

type Props = {
  service: TnService | null;
  /** The tapped spot; null = nothing tapped yet. */
  spot: Spot | null;
  unit: SpeedUnit;
  /** The speed lock (Fahrsperre) is in force: the limit may be read, but not proposed. */
  locked: boolean;
  /** Bumps when a proposal was stored, so the map screen can send it. */
  onSaved: () => void;
  onClose: () => void;
};

type Form = { kind: 'missing' } | { kind: 'wrong' } | null;

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

function unitLabel(unit: SpeedUnit): string {
  return unit === 'mph' ? 'mph' : 'km/h';
}

function originText(result: Extract<SpeedLimitLookup, { status: 'found' }>): string | null {
  switch (result.origin.kind) {
    case 'imported':
      return t('limit.origin.imported');
    case 'locallyProposed':
      return t('limit.origin.locallyProposed');
    case 'communityCorrected':
      return t('limit.origin.communityCorrected', { count: result.origin.confirmations });
  }
}

/** The bottom card of the "speed limit" mode: what is on record at the tapped spot, and — when standing — adding or correcting it. */
export function SpeedLimitCard({ service, spot, unit, locked, onSaved, onClose }: Props) {
  const theme = useTheme();
  const [lookup, setLookup] = useState<{ key: string; state: LookupState } | null>(null);
  const [form, setForm] = useState<Form>(null);
  const [value, setValue] = useState('');
  const [reason, setReason] = useState<WrongReason>('wrongValue');
  const [outcome, setOutcome] = useState<ProposalOutcome | 'saved' | null>(null);
  const [lookups, setLookups] = useState(0);

  // The parent keys this card by the tapped spot, so a new spot starts from a clean card.
  const lat = spot?.lat;
  const lng = spot?.lng;
  const key = `${lat},${lng},${lookups}`;
  useEffect(() => {
    if (!service || lat === undefined || lng === undefined) return;
    let cancelled = false;
    void lookupSpot(service, { lat, lng }).then((next) => {
      if (!cancelled) setLookup({ key: `${lat},${lng},${lookups}`, state: next });
    });
    return () => {
      cancelled = true;
    };
  }, [service, lat, lng, lookups]);

  const state: LookupState = !spot ? { phase: 'loading' } : lookup?.key === key ? lookup.state : { phase: 'loading' };
  const parsed = parseLimitValue(value, unit);

  const send = async () => {
    if (!service || !spot || !form || parsed === null) return;
    const result = form.kind === 'missing' ? await proposeMissing(service, spot, parsed, unit) : await proposeCorrection(service, spot, parsed, unit, reason);
    if (result.ok) {
      setOutcome('saved');
      setForm(null);
      onSaved();
      setLookups((n) => n + 1);
    } else {
      setOutcome(result);
      if (result.reason === 'roadAlreadyHasLimit') {
        setForm(null);
        setLookups((n) => n + 1);
      }
    }
  };

  const result = state.phase === 'done' ? state.result : null;
  const canPropose = result !== null && (result.status === 'found' || result.status === 'notRecorded');

  return (
    <View accessibilityViewIsModal style={[styles.card, squircle, elevation(theme, 2), { backgroundColor: theme.surface }]}>
      <View style={[styles.grabber, { backgroundColor: theme.border }]} />
      <View style={styles.header}>
        <Icon name="speedometer" size={24} color={theme.tint} />
        <Text accessibilityRole="header" style={[type.heading, styles.title, { color: theme.text }]}>
          {t('limit.title')}
        </Text>
        <Pressable accessibilityRole="button" accessibilityLabel={t('limit.close')} onPress={onClose} style={[styles.close, { backgroundColor: theme.surfaceAlt }]}>
          <Icon name="close" size={20} color={theme.text} />
        </Pressable>
      </View>

      {!spot ? <Text style={[type.body, { color: theme.textSecondary }]}>{t('limit.tapRoad')}</Text> : null}
      {spot && state.phase === 'loading' ? <Text style={[type.body, { color: theme.textSecondary }]}>{t('limit.loading')}</Text> : null}
      {state.phase === 'error' ? (
        <Text accessibilityRole="alert" style={[type.body, { color: theme.text }]}>
          {t('limit.error')}
        </Text>
      ) : null}
      {result?.status === 'found' ? (
        <View style={styles.found}>
          <Text accessibilityLabel={t('limit.found', { value: result.value, unit: unitLabel(result.unit) })} style={[styles.value, { color: theme.text }]}>
            {result.value} <Text style={[type.caption, { color: theme.textSecondary }]}>{unitLabel(result.unit)}</Text>
          </Text>
          <Text style={[type.caption, { color: theme.textSecondary }]}>{originText(result)}</Text>
        </View>
      ) : null}
      {result?.status === 'notRecorded' ? <Text style={[type.body, { color: theme.text }]}>{t('limit.notRecorded')}</Text> : null}
      {result?.status === 'outsideOfflineArea' ? (
        <Text accessibilityRole="alert" style={[type.body, { color: theme.text }]}>
          {t('limit.outside')}
        </Text>
      ) : null}

      {canPropose && !form ? (
        locked ? (
          <View accessibilityRole="alert" style={styles.lockedRow}>
            <Icon name="lock-closed" size={18} color={theme.textSecondary} />
            <Text style={[type.caption, styles.flex, { color: theme.textSecondary }]}>{t('limit.locked')}</Text>
          </View>
        ) : (
          <Button
            kind={result.status === 'notRecorded' ? 'primary' : 'plain'}
            label={result.status === 'notRecorded' ? t('limit.add') : t('limit.wrong')}
            onPress={() => {
              setOutcome(null);
              setForm({ kind: result.status === 'notRecorded' ? 'missing' : 'wrong' });
            }}
          />
        )
      ) : null}

      {form && !locked ? (
        <View style={styles.form}>
          <Text accessibilityRole="header" style={[type.label, { color: theme.textSecondary }]}>
            {t('limit.form.value', { unit: unitLabel(unit) })}
          </Text>
          <View style={styles.chips}>
            {QUICK_LIMITS[unit].map((q) => (
              <Chip key={q} label={String(q)} selected={parsed === q} onPress={() => setValue(String(q))} />
            ))}
            <TextInput
              accessibilityLabel={t('limit.form.input')}
              keyboardType="number-pad"
              inputMode="numeric"
              maxLength={3}
              value={value}
              onChangeText={setValue}
              placeholder={unitLabel(unit)}
              placeholderTextColor={theme.textSecondary}
              style={[styles.input, { color: theme.text, backgroundColor: theme.surfaceAlt, borderColor: theme.border }]}
            />
          </View>
          {form.kind === 'wrong' ? (
            <>
              <Text accessibilityRole="header" style={[type.label, { color: theme.textSecondary }]}>
                {t('limit.form.reason')}
              </Text>
              <View style={styles.chips}>
                {WRONG_REASONS.map((r) => (
                  <Chip key={r} label={t(`limit.reason.${r}`)} selected={reason === r} onPress={() => setReason(r)} />
                ))}
              </View>
            </>
          ) : null}
          <Text style={[type.caption, { color: theme.text, fontWeight: '600' }]}>{t('limit.safety')}</Text>
          <Text style={[type.caption, { color: theme.textSecondary }]}>{t('limit.privacy')}</Text>
          <View style={styles.buttons}>
            <View style={styles.flex}>
              <Button label={t('limit.send')} disabled={parsed === null} onPress={() => void send()} />
            </View>
            <View style={styles.flex}>
              <Button kind="plain" label={t('limit.cancel')} onPress={() => setForm(null)} />
            </View>
          </View>
        </View>
      ) : null}

      {outcome === 'saved' ? (
        <Text accessibilityRole="alert" style={[type.body, { color: theme.success }]}>
          {t('limit.saved')}
        </Text>
      ) : outcome && !outcome.ok ? (
        <Text accessibilityRole="alert" style={[type.body, { color: theme.text }]}>
          {t(`limit.error.${outcome.reason}`)}
        </Text>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  card: { borderRadius: radius.sheet, padding: 18, paddingTop: 10, gap: 10 },
  grabber: { alignSelf: 'center', width: 40, height: 5, borderRadius: 3, marginBottom: 6 },
  header: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  title: { flex: 1 },
  close: { width: MIN_TOUCH - 8, height: MIN_TOUCH - 8, borderRadius: (MIN_TOUCH - 8) / 2, alignItems: 'center', justifyContent: 'center' },
  found: { gap: 2 },
  value: { fontSize: 34, fontWeight: '800' },
  lockedRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  flex: { flex: 1 },
  form: { gap: 8 },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, alignItems: 'center' },
  chip: { minHeight: MIN_TOUCH - 4, paddingHorizontal: 14, borderRadius: radius.md, alignItems: 'center', justifyContent: 'center' },
  input: { minWidth: 80, minHeight: MIN_TOUCH - 4, borderRadius: radius.md, borderWidth: StyleSheet.hairlineWidth, paddingHorizontal: 12, fontSize: 16 },
  buttons: { flexDirection: 'row', gap: 10 },
});
