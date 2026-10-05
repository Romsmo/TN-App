import Constants from 'expo-constants';
import { Link } from 'expo-router';
import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { ConfirmDialog } from '@/components/confirm-dialog';
import { Icon, type IconName } from '@/components/icon';
import { Body, Group, LargeTitle, MIN_TOUCH, RowIcon, Segmented, Toggle } from '@/components/ui';
import { ALLOW_DISABLE_DRIVE_LOCK } from '@/config';
import { t, type TextKey } from '@/i18n';
import { hazardLabel } from '@/map/hazard-labels';
import { interimCatalog } from '@/report/catalog';
import { settingsStore, useSettings, type Settings } from '@/settings';
import { useCameraPolicy } from '@/state/camera-policy';
import { useTn } from '@/state/tn-provider';
import { hazardColor } from '@/map/colors';
import { hazardIcon } from '@/map/hazard-icons';
import { TAB_BAR_CLEARANCE, type, useTheme } from '@/theme';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { CamerasSwitch } from './cameras-switch';
import { LockSwitch } from './lock-switch';

type Entry = { href: '/server' | '/data' | '/info'; title: TextKey; hint: TextKey; icon: IconName; color: string };

const ENTRIES: Entry[] = [
  { href: '/server', title: 'settings.server', hint: 'settings.serverHint', icon: 'server', color: '#5856D6' },
  { href: '/data', title: 'settings.data', hint: 'settings.dataHint', icon: 'cloud-download', color: '#30B0C7' },
  { href: '/info', title: 'settings.info', hint: 'settings.infoHint', icon: 'information-circle', color: '#007AFF' },
];

function SwitchRow({ label, value, onChange, icon, color }: { label: string; value: boolean; onChange: (v: boolean) => void; icon?: IconName; color?: string }) {
  return (
    <View style={styles.row}>
      {icon ? <RowIcon name={icon} color={color} /> : null}
      <View style={styles.flex}>
        <Body>{label}</Body>
      </View>
      <Toggle accessibilityLabel={label} value={value} onValueChange={onChange} />
    </View>
  );
}

/** A tappable row that acts, in the system look: plain text, red when it destroys something. */
function ActionRow({ label, onPress, destructive }: { label: string; onPress: () => void; destructive?: boolean }) {
  const theme = useTheme();
  return (
    <Pressable accessibilityRole="button" accessibilityLabel={label} onPress={onPress} style={({ pressed }) => [styles.action, { opacity: pressed ? 0.5 : 1 }]}>
      <Text style={[styles.actionText, { color: destructive ? theme.danger : theme.tint }]}>{label}</Text>
    </Pressable>
  );
}

export function SettingsScreen() {
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const settings = useSettings();
  const tn = useTn();
  const policy = useCameraPolicy(tn.service, tn.dataVersion);
  const [confirm, setConfirm] = useState<'data' | 'identity' | null>(null);
  const [done, setDone] = useState(false);
  const [failed, setFailed] = useState(false);

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
    setDone(false);
    setFailed(false);
    try {
      if (what === 'data') {
        await tn.resetLocalData();
        settingsStore.reset();
      } else if (what === 'identity') {
        await tn.resetDeviceIdentity();
        set({ driveLockEnabled: true }); // after a reset the lock is on again, whatever it was
      }
      setDone(true);
    } catch {
      setFailed(true);
    }
  };

  return (
    <ScrollView style={{ backgroundColor: theme.background }} contentContainerStyle={[styles.content, { paddingTop: insets.top + 12 }]}>
      <LargeTitle>{t('tabs.settings')}</LargeTitle>

      <Group title={t('settings.section.drive')}>
        <View style={styles.stack}>
          <Body>{t('settings.units')}</Body>
          <Segmented label={t('settings.units')} value={settings.speedUnit} onChange={(speedUnit) => set({ speedUnit })} options={[{ value: 'kmh', label: 'km/h' }, { value: 'mph', label: 'mph' }]} />
        </View>
        <SwitchRow icon="volume-high" color="#FF9500" label={t('settings.sound')} value={settings.driveSound} onChange={(driveSound) => set({ driveSound })} />
        <SwitchRow icon="chatbubble-ellipses" color="#34C759" label={t('settings.voice')} value={settings.driveVoice} onChange={(driveVoice) => set({ driveVoice })} />
        <View style={styles.stack}>
          <Body>{t('settings.scale')}</Body>
          <Segmented
            label={t('settings.scale')}
            value={settings.warnScale}
            onChange={(warnScale) => set({ warnScale })}
            options={[{ value: 0.75, label: t('settings.scale.near') }, { value: 1, label: t('settings.scale.normal') }, { value: 1.5, label: t('settings.scale.far') }]}
          />
        </View>
      </Group>

      <Group title={t('settings.warnCategories')}>
        {warnTypes.map((category) => {
          const label = category === 'cameras' ? t('settings.section.cameras') : hazardLabel(category);
          return (
            <SwitchRow
              key={category}
              icon={hazardIcon(category)}
              color={category === 'cameras' ? hazardColor('fixedSpeedCamera') : hazardColor(category)}
              label={t('settings.warnCategory', { type: label })}
              value={!settings.warnOffCategories.includes(category)}
              onChange={(on) => toggleWarn(category, on)}
            />
          );
        })}
      </Group>

      <Group title={t('settings.section.cameras')}>
        <CamerasSwitch
          enabled={settings.camerasEnabled}
          onChange={(camerasEnabled) => set({ camerasEnabled })}
          maxLevel={policy?.maxLevel ?? null}
          noticeSeen={settings.camerasNoticeSeen}
          serverNoticeVersion={policy?.notice.version ?? null}
          onNoticeSeen={(camerasNoticeSeen) => set({ camerasNoticeSeen })}
        />
      </Group>

      <Group title={t('settings.section.safety')}>
        {ALLOW_DISABLE_DRIVE_LOCK ? (
          <LockSwitch enabled={settings.driveLockEnabled} onChange={(driveLockEnabled) => set({ driveLockEnabled })} />
        ) : (
          <Body secondary>{t('lockSwitch.always')}</Body>
        )}
      </Group>

      <Group title={t('settings.section.more')}>
        {ENTRIES.map((entry) => (
          <Link key={entry.href} href={entry.href} asChild>
            <Pressable accessibilityRole="link" accessibilityLabel={`${t(entry.title)}, ${t(entry.hint)}`} style={styles.entry}>
              <RowIcon name={entry.icon} color={entry.color} />
              <View style={styles.flex}>
                <Text style={[styles.entryTitle, { color: theme.text }]}>{t(entry.title)}</Text>
                <Text style={[type.caption, { color: theme.textSecondary }]}>{t(entry.hint)}</Text>
              </View>
              <Icon name="chevron-forward" size={18} color={theme.textSecondary} />
            </Pressable>
          </Link>
        ))}
      </Group>

      <Group title={t('settings.section.data')} footer={`${t('settings.deleteLocalHint')}\n\n${t('settings.resetIdentityHint')}`}>
        <ActionRow destructive label={t('settings.deleteLocal')} onPress={() => setConfirm('data')} />
        <ActionRow destructive label={t('settings.resetIdentity')} onPress={() => setConfirm('identity')} />
        {done ? <Body secondary>{t('settings.done')}</Body> : null}
        {failed ? <Body secondary>{t('settings.failed')}</Body> : null}
      </Group>

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
  content: { paddingHorizontal: 16, paddingBottom: TAB_BAR_CLEARANCE + 16, gap: 22 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  flex: { flex: 1 },
  entry: { minHeight: MIN_TOUCH, flexDirection: 'row', alignItems: 'center', gap: 12 },
  stack: { gap: 8 },
  action: { minHeight: MIN_TOUCH - 8, justifyContent: 'center' },
  actionText: { fontSize: 17 },
  entryTitle: { fontSize: 17, fontWeight: '600' },
  version: { textAlign: 'center', fontSize: 13 },
});
