import { useKeepAwake } from 'expo-keep-awake';
import { useEffect, useRef, useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';

import { ConfirmDialog } from '@/components/confirm-dialog';
import { Body, Button } from '@/components/ui';
import { useDriveHost, useDriveSnapshot } from '@/drive/drive-provider';
import type { DriveMode } from '@/drive/drive-host';
import { getLanguage, t } from '@/i18n';
import { CAMERA_NOTICE, DRIVE_NOTICE_EXTRA, type Segment } from '@/legal/texts';
import { settingsStore, useSettings } from '@/settings';
import { CAMERA_TYPES } from '@/map/camera-types';
import { useCameraPolicy } from '@/state/camera-policy';
import { useTn } from '@/state/tn-provider';
import { TAB_BAR_CLEARANCE, type, useTheme } from '@/theme';

import { DriveView } from './drive-view';

/** The one-tap report buttons: the most common hazards, plus all camera types only where cameras are on and allowed in full. */
export function driveReportTypes(camerasActive: boolean, maxLevel: 'off' | 'zones' | 'full' | null): string[] {
  const types: string[] = ['traffic', 'accident', 'construction', 'ice'];
  if (camerasActive && maxLevel === 'full') types.push(...CAMERA_TYPES);
  return types;
}

function RunningDrive() {
  useKeepAwake(); // the screen stays on while the drive mode runs
  const host = useDriveHost();
  const snapshot = useDriveSnapshot();
  const settings = useSettings();
  const tn = useTn();
  const policy = useCameraPolicy(tn.service, tn.dataVersion);
  const [toast, setToast] = useState<string | null>(null);
  const toastTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => () => void (toastTimer.current && clearTimeout(toastTimer.current)), []);

  if (!snapshot) return null;
  const session = host.current;

  const showToast = (text: string) => {
    setToast(text);
    if (toastTimer.current) clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setToast(null), 2000);
  };

  return (
    <DriveView
      snapshot={snapshot}
      unit={settings.speedUnit}
      lockEnabled={settings.driveLockEnabled}
      emergency={tn.emergency !== null}
      reportTypes={driveReportTypes(settings.camerasEnabled && policy?.active === true, policy?.maxLevel ?? null)}
      toast={toast}
      onReport={(type) => void session?.report(type).then((ok) => showToast(ok ? t('drive.reported') : t('drive.reportFailed')))}
      onAnswer={(stillThere) => void session?.answerPrompt(stillThere)}
      onMute={() => session?.setMuted(!snapshot.muted)}
      onStop={() => host.stop()}
      onEnableLock={() => settingsStore.update({ driveLockEnabled: true })}
    />
  );
}

/** The notice at the first start of the drive mode: the camera notice, plus the hint to operate the app only as a passenger or when stationary. */
function startNotice(): Segment[] {
  const language = getLanguage();
  return [...CAMERA_NOTICE[language], { text: `\n\n${DRIVE_NOTICE_EXTRA[language]}` }];
}

export function DriveScreen() {
  const theme = useTheme();
  const host = useDriveHost();
  const snapshot = useDriveSnapshot();
  const { driveNoticeSeen } = useSettings();
  const tn = useTn();
  const [pending, setPending] = useState<{ mode: DriveMode; speedup: number } | null>(null);
  const [starting, setStarting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const begin = (mode: DriveMode, speedup: number) => {
    setError(null);
    setStarting(true);
    host
      .start(mode, { speedup })
      .catch(() => setError(t('drive.noPermission')))
      .finally(() => setStarting(false));
  };
  const request = (mode: DriveMode, speedup = 1) => (driveNoticeSeen ? begin(mode, speedup) : setPending({ mode, speedup }));

  if (snapshot?.active) return <RunningDrive />;

  return (
    <ScrollView style={{ backgroundColor: theme.background }} contentContainerStyle={styles.content}>
      <View style={styles.box}>
        <Text accessibilityRole="header" style={[type.title, { color: theme.text }]}>
          {t('tabs.drive')}
        </Text>
        <Body secondary>{t('drive.startHint')}</Body>
        {tn.emergency ? <Body secondary>{t('emergency.driveHint')}</Body> : null}
        <Button icon="play-circle" label={starting ? t('drive.starting') : t('drive.start')} disabled={starting} onPress={() => request('real')} />
        <Body secondary>{t('drive.simulateHint')}</Body>
        <Button kind="plain" icon="flask" label={t('drive.simulate')} disabled={starting} onPress={() => request('simulation')} />
        <Button kind="plain" icon="flash" label={t('drive.simulateFast')} disabled={starting} onPress={() => request('simulation', 4)} />
        {error ? (
          <Text accessibilityRole="alert" style={{ color: theme.danger, fontSize: 16 }}>
            {error}
          </Text>
        ) : null}
      </View>
      <ConfirmDialog
        visible={pending !== null}
        title={t('driveNotice.title')}
        body={startNotice()}
        confirmLabel={t('driveNotice.ok')}
        onConfirm={() => {
          const next = pending;
          setPending(null);
          settingsStore.update({ driveNoticeSeen: true });
          if (next) begin(next.mode, next.speedup);
        }}
      />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  content: { flexGrow: 1, justifyContent: 'center', padding: 20, paddingBottom: TAB_BAR_CLEARANCE + 16 },
  box: { gap: 12 },
});
