import Constants from 'expo-constants';
import { Link } from 'expo-router';
import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Switch, Text, View } from 'react-native';

import { ConfirmDialog } from '@/components/confirm-dialog';
import { Body, Button, MIN_TOUCH, Section } from '@/components/ui';
import { ALLOW_DISABLE_DRIVE_LOCK } from '@/config';
import { t, type TextKey } from '@/i18n';
import { hazardLabel } from '@/map/hazard-labels';
import { interimCatalog } from '@/report/catalog';
import { settingsStore, useSettings, type Settings } from '@/settings';
import { useCameraPolicy } from '@/state/camera-policy';
import { useTn } from '@/state/tn-provider';
import { useTheme } from '@/theme';

import { CamerasSwitch } from './cameras-switch';
import { LockSwitch } from './lock-switch';

type Entry = { href: '/server' | '/data' | '/info'; title: TextKey; hint: TextKey };

const ENTRIES: Entry[] = [
  { href: '/server', title: 'settings.server', hint: 'settings.serverHint' },
  { href: '/data', title: 'settings.data', hint: 'settings.dataHint' },
  { href: '/info', title: 'settings.info', hint: 'settings.infoHint' },
];

function Choice<T extends string | number>({ label, options, value, onChange }: { label: string; options: { value: T; label: string }[]; value: T; onChange: (v: T) => void }) {
  return (
    <View accessibilityRole="radiogroup" accessibilityLabel={label} style={styles.choiceRow}>
      {options.map((o) => (
        <View key={String(o.value)} style={styles.flex}>
          <Button kind={o.value === value ? 'primary' : 'plain'} label={o.label} accessibilityState={{ selected: o.value === value }} onPress={() => onChange(o.value)} />
        </View>
      ))}
    </View>
  );
}

function SwitchRow({ label, value, onChange }: { label: string; value: boolean; onChange: (v: boolean) => void }) {
  return (
    <View style={styles.row}>
      <View style={styles.flex}>
        <Body>{label}</Body>
      </View>
      <Switch accessibilityLabel={label} value={value} onValueChange={onChange} />
    </View>
  );
}

export function SettingsScreen() {
  const theme = useTheme();
  const settings = useSettings();
  const tn = useTn();
  const policy = useCameraPolicy(tn.service, tn.dataVersion);
  const [confirm, setConfirm] = useState<'data' | 'identity' | null>(null);
  const [done, setDone] = useState(false);

  const set = (patch: Partial<Settings>) => settingsStore.update(patch);
  const warnTypes = [...interimCatalog.types(), ...(settings.camerasEnabled ? ['cameras'] : [])];
  const toggleWarn = (category: string, on: boolean) => {
    const off = new Set(settings.warnOffCategories);
    if (on) off.delete(category);
    else off.add(category);
    set({ warnOffCategories: [...off] });
  };

  const runConfirmed = async () => {
    const what = confirm;
    setConfirm(null);
    if (what === 'data') {
      await tn.resetLocalData();
      settingsStore.reset();
    } else if (what === 'identity') {
      await tn.resetDeviceIdentity();
      set({ driveLockEnabled: true }); // after a reset the lock is on again, whatever it was
    }
    setDone(true);
  };

  return (
    <ScrollView style={{ backgroundColor: theme.background }} contentContainerStyle={styles.content}>
      <Section title={t('settings.section.drive')}>
        <Body>{t('settings.units')}</Body>
        <Choice label={t('settings.units')} value={settings.speedUnit} onChange={(speedUnit) => set({ speedUnit })} options={[{ value: 'kmh', label: 'km/h' }, { value: 'mph', label: 'mph' }]} />
        <SwitchRow label={t('settings.sound')} value={settings.driveSound} onChange={(driveSound) => set({ driveSound })} />
        <SwitchRow label={t('settings.voice')} value={settings.driveVoice} onChange={(driveVoice) => set({ driveVoice })} />
        <Body>{t('settings.scale')}</Body>
        <Choice
          label={t('settings.scale')}
          value={settings.warnScale}
          onChange={(warnScale) => set({ warnScale })}
          options={[{ value: 0.75, label: t('settings.scale.near') }, { value: 1, label: t('settings.scale.normal') }, { value: 1.5, label: t('settings.scale.far') }]}
        />
        <Body>{t('settings.warnCategories')}</Body>
        {warnTypes.map((category) => {
          const label = category === 'cameras' ? t('settings.section.cameras') : hazardLabel(category);
          return <SwitchRow key={category} label={t('settings.warnCategory', { type: label })} value={!settings.warnOffCategories.includes(category)} onChange={(on) => toggleWarn(category, on)} />;
        })}
      </Section>

      <Section title={t('settings.section.cameras')}>
        <CamerasSwitch
          enabled={settings.camerasEnabled}
          onChange={(camerasEnabled) => set({ camerasEnabled })}
          maxLevel={policy?.maxLevel ?? null}
          noticeSeen={settings.camerasNoticeSeen}
          serverNoticeVersion={policy?.notice.version ?? null}
          onNoticeSeen={(camerasNoticeSeen) => set({ camerasNoticeSeen })}
        />
      </Section>

      <Section title={t('settings.section.safety')}>
        {ALLOW_DISABLE_DRIVE_LOCK ? (
          <LockSwitch enabled={settings.driveLockEnabled} onChange={(driveLockEnabled) => set({ driveLockEnabled })} />
        ) : (
          <Body secondary>{t('lockSwitch.always')}</Body>
        )}
      </Section>

      <Section title={t('settings.section.more')}>
        {ENTRIES.map((entry) => (
          <Link key={entry.href} href={entry.href} asChild>
            <Pressable accessibilityRole="link" accessibilityLabel={`${t(entry.title)}, ${t(entry.hint)}`} style={styles.entry}>
              <View>
                <Text style={[styles.entryTitle, { color: theme.text }]}>{t(entry.title)}</Text>
                <Text style={[styles.hint, { color: theme.textSecondary }]}>{t(entry.hint)}</Text>
              </View>
            </Pressable>
          </Link>
        ))}
      </Section>

      <Section title={t('settings.section.data')}>
        <Body secondary>{t('settings.deleteLocalHint')}</Body>
        <Button kind="plain" label={t('settings.deleteLocal')} onPress={() => setConfirm('data')} />
        <Body secondary>{t('settings.resetIdentityHint')}</Body>
        <Button kind="plain" label={t('settings.resetIdentity')} onPress={() => setConfirm('identity')} />
        {done ? <Body secondary>{t('settings.done')}</Body> : null}
      </Section>

      <Text style={[styles.version, { color: theme.textSecondary }]}>{t('settings.version', { version: Constants.expoConfig?.version ?? '?' })}</Text>

      <ConfirmDialog
        visible={confirm !== null}
        title={confirm === 'identity' ? t('settings.resetIdentity') : t('settings.deleteLocal')}
        body={confirm === 'identity' ? t('settings.resetIdentityHint') : t('settings.deleteLocalHint')}
        confirmLabel={confirm === 'identity' ? t('settings.resetIdentityConfirm') : t('settings.deleteLocalConfirm')}
        cancelLabel={t('common.cancel')}
        onConfirm={() => void runConfirmed()}
        onCancel={() => setConfirm(null)}
      />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, gap: 18 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  flex: { flex: 1 },
  choiceRow: { flexDirection: 'row', gap: 8 },
  entry: { minHeight: MIN_TOUCH, justifyContent: 'center' },
  entryTitle: { fontSize: 17, fontWeight: '600' },
  hint: { fontSize: 14 },
  version: { textAlign: 'center', fontSize: 13 },
});
