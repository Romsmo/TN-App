import { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { Icon } from '@/components/icon';
import { MIN_TOUCH } from '@/components/ui';
import { drivePalette as c } from '@/drive/palette';
import type { DriveSnapshot } from '@/drive/drive-session';
import { displayLimit, displaySpeed, unitLabel } from '@/drive/units';
import { t, type TextKey } from '@/i18n';
import { isCameraType } from '@/map/camera-types';
import { hazardColor } from '@/map/colors';
import { hazardIcon } from '@/map/hazard-icons';
import { hazardLabel } from '@/map/hazard-labels';
import type { SpeedUnit } from '@/tn/types';
import { radius, TAB_BAR_CLEARANCE } from '@/theme';

/** Big touch targets for the one-tap reports: far above the usual minimum. */
export const DRIVE_TOUCH = 84;

type Props = {
  snapshot: DriveSnapshot;
  unit: SpeedUnit;
  lockEnabled: boolean;
  /** The emergency mode: no data has ever been loaded, so there is no limit and no warning, only the speed. */
  emergency?: boolean;
  reportTypes: readonly string[];
  /** Short feedback line after a report ("Gemeldet"), or null. */
  toast: string | null;
  onReport: (type: string) => void;
  onAnswer: (stillThere: boolean) => void;
  onMute: () => void;
  onStop: () => void;
  /** Tapping the "lock off" badge switches the lock on again, without any confirmation. */
  onEnableLock: () => void;
};

/**
 * The drive-mode screen: only what is needed. Speed and limit, warnings ahead, one-tap reports, the "still there?" card.
 * Everything is large and high-contrast; there is no menu and no text input.
 */
export function DriveView({ snapshot, unit, lockEnabled, emergency = false, reportTypes, toast, onReport, onAnswer, onMute, onStop, onEnableLock }: Props) {
  const speed = displaySpeed(snapshot.speedKmh, unit);
  const limit = snapshot.limit ? displayLimit(snapshot.limit.value, snapshot.limit.unit, unit) : null;
  const over = snapshot.speedState === 'over';
  // The camera kinds sit behind one "Blitzer" tile, so the first screen keeps its few, large buttons.
  const [cameraPanel, setCameraPanel] = useState(false);
  const cameraTypes = reportTypes.filter(isCameraType);
  const plainTypes = reportTypes.filter((type) => !isCameraType(type));
  const report = (type: string) => {
    setCameraPanel(false);
    onReport(type);
  };

  return (
    <View style={styles.screen}>
      <View style={styles.chips}>
        {snapshot.simulated ? (
          <View accessibilityRole="alert" style={[styles.chip, { backgroundColor: c.tint }]}>
            <Icon name="flask" size={16} color={c.onTint} />
            <Text style={[styles.chipText, { color: c.onTint }]}>{t('drive.simulated')}</Text>
          </View>
        ) : null}
        {emergency ? (
          <View accessibilityRole="alert" style={[styles.chip, { backgroundColor: c.badge }]}>
            <Icon name="cloud-offline" size={16} color={c.text} />
            <Text style={[styles.chipText, { color: c.text }]}>{t('emergency.driveChip')}</Text>
          </View>
        ) : null}
        {snapshot.gpsLost ? (
          <View accessibilityRole="alert" style={[styles.chip, { backgroundColor: c.badge }]}>
            <Icon name="cellular" size={16} color={c.text} />
            <Text style={[styles.chipText, { color: c.text }]}>{t('drive.noGps')}</Text>
          </View>
        ) : null}
        {!lockEnabled ? (
          <Pressable accessibilityRole="button" accessibilityLabel={t('drive.lockOff')} accessibilityHint={t('drive.lockOffHint')} onPress={onEnableLock} style={[styles.chip, styles.chipTap, { backgroundColor: c.badge }]}>
            <Icon name="lock-open" size={16} color={c.text} />
            <Text style={[styles.chipText, { color: c.text }]}>{t('drive.lockOff')}</Text>
          </Pressable>
        ) : null}
      </View>

      <View style={styles.top}>
        <View accessible accessibilityLabel={`${speed ?? '—'} ${unitLabel(unit)}${over ? ', ' + t('drive.overLimit') : ''}`} style={styles.speedBox}>
          <Text style={[styles.speed, { color: over ? c.over : c.ok }]}>{speed ?? '—'}</Text>
          <Text style={[styles.unit, { color: c.textSecondary }]}>{unitLabel(unit)}</Text>
        </View>
        {limit !== null ? (
          <View accessible accessibilityLabel={t('drive.limit', { value: limit })} style={[styles.limit, { backgroundColor: c.sign, borderColor: c.signRing }]}>
            <Text style={[styles.limitText, { color: c.signInk }]}>{limit}</Text>
          </View>
        ) : null}
      </View>

      <View style={styles.warnings} accessibilityLiveRegion="assertive">
        {snapshot.warnings.length === 0 ? (
          <View style={styles.calmBox}>
            <Icon name={snapshot.speedKmh === null ? 'locate' : emergency ? 'cloud-offline' : 'radio'} size={28} color={c.textSecondary} />
            <Text style={[styles.calm, { color: c.textSecondary }]}>{snapshot.speedKmh === null ? t('drive.waiting') : emergency ? t('emergency.driveCalm') : t('drive.watching')}</Text>
          </View>
        ) : (
          snapshot.warnings.map((w) => {
            const second = w.level === 'second';
            return (
              <View
                key={w.id}
                accessible
                accessibilityLabel={w.kind === 'zone' ? t('drive.warnZone') : t('drive.warnPoint', { what: w.label, distance: w.distanceM ?? 0 })}
                style={[styles.warning, { backgroundColor: second ? c.warnSecond : c.warnFirst }]}>
                <View style={[styles.warningIcon, { backgroundColor: c.onWarn }]}>
                  <Icon name={hazardIcon(w.kind === 'zone' ? 'zone' : w.category)} size={30} color={second ? c.warnSecond : c.warnFirst} />
                </View>
                <View style={styles.warningText}>
                  <Text style={[styles.warningTitle, { color: c.onWarn }]}>{w.label}</Text>
                  <Text style={[styles.warningSub, { color: c.onWarn }]}>{w.kind === 'zone' ? t('drive.zoneHint') : t('drive.inMeters', { distance: w.distanceM ?? 0 })}</Text>
                </View>
              </View>
            );
          })
        )}
      </View>

      {snapshot.prompt ? (
        <View accessibilityViewIsModal accessibilityLiveRegion="assertive" style={[styles.prompt, { backgroundColor: c.surface }]}>
          <Text style={[styles.promptTitle, { color: c.text }]}>{t('drive.stillThere', { what: hazardLabel(snapshot.prompt.hazardType) })}</Text>
          <View style={styles.row}>
            <BigButton label={t('vote.still')} kind="primary" icon="checkmark-circle" onPress={() => onAnswer(true)} />
            <BigButton label={t('vote.gone')} kind="plain" icon="close-circle" onPress={() => onAnswer(false)} />
          </View>
        </View>
      ) : null}

      {toast ? (
        <Text accessibilityRole="alert" style={[styles.toast, { color: c.text, backgroundColor: c.surface }]}>
          {toast}
        </Text>
      ) : null}

      {cameraPanel ? (
        <View style={styles.reports}>
          <Text style={[styles.panelTitle, { color: c.text }]}>{t('drive.report.cameraTitle')}</Text>
          {cameraTypes.map((type) => (
            <ReportTile key={type} type={type} short onPress={() => report(type)} />
          ))}
          <Pressable accessibilityRole="button" accessibilityLabel={t('common.back')} onPress={() => setCameraPanel(false)} style={({ pressed }) => [styles.tile, { backgroundColor: c.tile, opacity: pressed ? 0.8 : 1 }]}>
            <Icon name="chevron-back" size={26} color={c.text} />
            <Text style={[styles.tileText, { color: c.text }]}>{t('common.back')}</Text>
          </Pressable>
        </View>
      ) : (
        <View style={styles.reports}>
          {plainTypes.map((type) => (
            <ReportTile key={type} type={type} onPress={() => report(type)} />
          ))}
          {cameraTypes.length > 0 ? (
            <Pressable
              accessibilityRole="button"
              accessibilityLabel={t('drive.report.cameras')}
              onPress={() => setCameraPanel(true)}
              style={({ pressed }) => [styles.tile, { backgroundColor: c.tile, opacity: pressed ? 0.8 : 1 }]}>
              <View style={[styles.tileIcon, { backgroundColor: hazardColor('cameras') }]}>
                <Icon name={hazardIcon('cameras')} size={26} color="#FFFFFF" />
              </View>
              <Text style={[styles.tileText, { color: c.text }]}>{t('drive.report.cameras')}</Text>
            </Pressable>
          ) : null}
        </View>
      )}

      <View style={styles.row}>
        <BigButton label={snapshot.muted ? t('drive.unmute') : t('drive.mute')} kind="plain" icon={snapshot.muted ? 'volume-high' : 'volume-mute'} onPress={onMute} />
        <BigButton label={t('drive.stop')} kind="plain" icon="stop-circle" onPress={onStop} />
      </View>
    </View>
  );
}

/** One report button. `short` is the camera panel: five kinds side by side need one-word labels (the spoken label stays full). */
function ReportTile({ type, onPress, short = false }: { type: string; onPress: () => void; short?: boolean }) {
  const key = `drive.camera.${type}` as TextKey;
  const label = short ? t(key) : hazardLabel(type);
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={t('report.type', { type: hazardLabel(type) })}
      onPress={onPress}
      style={({ pressed }) => [styles.tile, short ? styles.tileShort : null, { backgroundColor: c.tile, opacity: pressed ? 0.8 : 1 }]}>
      <View style={[styles.tileIcon, short ? styles.tileIconShort : null, { backgroundColor: hazardColor(type) }]}>
        <Icon name={hazardIcon(type)} size={short ? 20 : 26} color="#FFFFFF" />
      </View>
      <Text numberOfLines={short ? 1 : undefined} style={[styles.tileText, short ? styles.tileTextShort : null, { color: c.text }]}>
        {label}
      </Text>
    </Pressable>
  );
}

function BigButton({ label, kind, icon, onPress }: { label: string; kind: 'primary' | 'plain'; icon: 'checkmark-circle' | 'close-circle' | 'volume-high' | 'volume-mute' | 'stop-circle'; onPress: () => void }) {
  const primary = kind === 'primary';
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      onPress={onPress}
      style={({ pressed }) => [styles.big, { backgroundColor: primary ? c.tint : c.tile, opacity: pressed ? 0.8 : 1 }]}>
      <Icon name={icon} size={26} color={primary ? c.onTint : c.text} />
      <Text style={[styles.bigText, { color: primary ? c.onTint : c.text }]}>{label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  // the drive mode has its own full-bleed dark ground; the bottom padding keeps the buttons clear of the floating tab bar
  screen: { flex: 1, backgroundColor: c.background, padding: 14, paddingTop: 20, paddingBottom: TAB_BAR_CLEARANCE, gap: 10 },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  chip: { flexDirection: 'row', alignItems: 'center', gap: 6, paddingHorizontal: 12, paddingVertical: 7, borderRadius: radius.pill },
  chipTap: { minHeight: MIN_TOUCH - 8 },
  chipText: { fontSize: 14, fontWeight: '800' },
  top: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 4 },
  speedBox: { flexDirection: 'row', alignItems: 'flex-end', gap: 8 },
  speed: { fontSize: 112, fontWeight: '800', lineHeight: 120, letterSpacing: -4, fontVariant: ['tabular-nums'] },
  unit: { fontSize: 24, fontWeight: '600', paddingBottom: 18 },
  limit: { width: 96, height: 96, borderRadius: 48, borderWidth: 9, alignItems: 'center', justifyContent: 'center' },
  limitText: { fontSize: 38, fontWeight: '800', letterSpacing: -1 },
  warnings: { flex: 1, gap: 10, justifyContent: 'center' },
  calmBox: { alignItems: 'center', gap: 8 },
  calm: { fontSize: 18, textAlign: 'center' },
  warning: { borderRadius: radius.lg, padding: 14, flexDirection: 'row', alignItems: 'center', gap: 14 },
  warningIcon: { width: 56, height: 56, borderRadius: 28, alignItems: 'center', justifyContent: 'center' },
  warningText: { flex: 1 },
  warningTitle: { fontSize: 32, fontWeight: '800', letterSpacing: -0.5 },
  warningSub: { fontSize: 22, fontWeight: '700' },
  prompt: { borderRadius: radius.lg, padding: 14, gap: 10 },
  promptTitle: { fontSize: 26, fontWeight: '800' },
  toast: { textAlign: 'center', fontSize: 20, fontWeight: '700', paddingVertical: 10, borderRadius: radius.md, overflow: 'hidden' },
  panelTitle: { width: '100%', fontSize: 20, fontWeight: '800', paddingHorizontal: 4 },
  reports: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 },
  tile: { flexGrow: 1, flexBasis: '45%', minHeight: DRIVE_TOUCH, borderRadius: radius.lg, flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 14 },
  tileIcon: { width: 48, height: 48, borderRadius: 24, alignItems: 'center', justifyContent: 'center' },
  tileShort: { paddingHorizontal: 12, gap: 10 },
  tileIconShort: { width: 36, height: 36, borderRadius: 18 },
  tileTextShort: { fontSize: 19 },
  tileText: { fontSize: 20, fontWeight: '800', flexShrink: 1 },
  row: { flexDirection: 'row', gap: 10 },
  big: { flexGrow: 1, flexBasis: '45%', minHeight: DRIVE_TOUCH - 16, borderRadius: radius.pill, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, paddingHorizontal: 12 },
  bigText: { fontSize: 20, fontWeight: '800', textAlign: 'center', flexShrink: 1 },
});
