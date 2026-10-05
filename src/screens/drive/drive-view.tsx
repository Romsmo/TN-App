import { StyleSheet, Text, View, Pressable } from 'react-native';

import { MIN_TOUCH } from '@/components/ui';
import { drivePalette as c } from '@/drive/palette';
import type { DriveSnapshot } from '@/drive/drive-session';
import { displayLimit, displaySpeed, unitLabel } from '@/drive/units';
import { t } from '@/i18n';
import { hazardLabel } from '@/map/hazard-labels';
import type { SpeedUnit } from '@/tn/types';

/** Big touch targets for the one-tap reports: far above the usual minimum. */
export const DRIVE_TOUCH = 84;

type Props = {
  snapshot: DriveSnapshot;
  unit: SpeedUnit;
  lockEnabled: boolean;
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
export function DriveView({ snapshot, unit, lockEnabled, reportTypes, toast, onReport, onAnswer, onMute, onStop, onEnableLock }: Props) {
  const speed = displaySpeed(snapshot.speedKmh, unit);
  const limit = snapshot.limit ? displayLimit(snapshot.limit.value, snapshot.limit.unit, unit) : null;
  const over = snapshot.speedState === 'over';

  return (
    <View style={styles.screen}>
      {snapshot.simulated ? (
        <Text accessibilityRole="alert" style={[styles.banner, { backgroundColor: c.tint, color: c.onTint }]}>
          {t('drive.simulated')}
        </Text>
      ) : null}
      {snapshot.gpsLost ? (
        <Text accessibilityRole="alert" style={[styles.banner, { backgroundColor: c.badge, color: c.text }]}>
          {t('drive.noGps')}
        </Text>
      ) : null}
      {!lockEnabled ? (
        <Pressable accessibilityRole="button" accessibilityLabel={t('drive.lockOff')} accessibilityHint={t('drive.lockOffHint')} onPress={onEnableLock} style={[styles.badge, { backgroundColor: c.badge }]}>
          <Text style={[styles.badgeText, { color: c.text }]}>{t('drive.lockOff')}</Text>
        </Pressable>
      ) : null}

      <View style={styles.top}>
        <View accessible accessibilityLabel={`${speed ?? '—'} ${unitLabel(unit)}${over ? ', ' + t('drive.overLimit') : ''}`} style={styles.speedBox}>
          <Text style={[styles.speed, { color: over ? c.over : c.ok }]}>{speed ?? '—'}</Text>
          <Text style={[styles.unit, { color: c.textSecondary }]}>{unitLabel(unit)}</Text>
        </View>
        {limit !== null ? (
          <View accessible accessibilityLabel={t('drive.limit', { value: limit })} style={[styles.limit, { borderColor: over ? c.over : c.text }]}>
            <Text style={[styles.limitText, { color: c.text }]}>{limit}</Text>
          </View>
        ) : null}
      </View>

      <View style={styles.warnings} accessibilityLiveRegion="assertive">
        {snapshot.warnings.length === 0 ? (
          <Text style={[styles.calm, { color: c.textSecondary }]}>{snapshot.speedKmh === null ? t('drive.waiting') : ''}</Text>
        ) : (
          snapshot.warnings.map((w) => (
            <View
              key={w.id}
              accessible
              accessibilityLabel={w.kind === 'zone' ? t('drive.warnZone') : t('drive.warnPoint', { what: w.label, distance: w.distanceM ?? 0 })}
              style={[styles.warning, { borderColor: w.level === 'second' ? c.warnSecond : c.warnFirst }]}>
              <Text style={[styles.warningTitle, { color: c.text }]}>{w.label}</Text>
              <Text style={[styles.warningSub, { color: w.level === 'second' ? c.warnSecond : c.warnFirst }]}>
                {w.kind === 'zone' ? t('drive.zoneHint') : t('drive.inMeters', { distance: w.distanceM ?? 0 })}
              </Text>
            </View>
          ))
        )}
      </View>

      {snapshot.prompt ? (
        <View accessibilityViewIsModal accessibilityLiveRegion="assertive" style={[styles.prompt, { backgroundColor: c.surface }]}>
          <Text style={[styles.promptTitle, { color: c.text }]}>{t('drive.stillThere', { what: hazardLabel(snapshot.prompt.hazardType) })}</Text>
          <View style={styles.row}>
            <BigButton label={t('vote.still')} kind="primary" onPress={() => onAnswer(true)} />
            <BigButton label={t('vote.gone')} kind="plain" onPress={() => onAnswer(false)} />
          </View>
        </View>
      ) : null}

      {toast ? (
        <Text accessibilityRole="alert" style={[styles.toast, { color: c.text, backgroundColor: c.surface }]}>
          {toast}
        </Text>
      ) : null}

      <View style={styles.reports}>
        {reportTypes.map((type) => (
          <BigButton key={type} label={hazardLabel(type)} kind="primary" a11yLabel={t('report.type', { type: hazardLabel(type) })} onPress={() => onReport(type)} />
        ))}
      </View>

      <View style={styles.row}>
        <BigButton label={snapshot.muted ? t('drive.unmute') : t('drive.mute')} kind="plain" onPress={onMute} />
        <BigButton label={t('drive.stop')} kind="plain" onPress={onStop} />
      </View>
    </View>
  );
}

function BigButton({ label, kind, onPress, a11yLabel }: { label: string; kind: 'primary' | 'plain'; onPress: () => void; a11yLabel?: string }) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={a11yLabel ?? label}
      onPress={onPress}
      style={({ pressed }) => [styles.big, { backgroundColor: kind === 'primary' ? c.tint : c.surface, opacity: pressed ? 0.8 : 1 }]}>
      <Text style={[styles.bigText, { color: kind === 'primary' ? c.onTint : c.text }]}>{label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: c.background, padding: 12, gap: 10 },
  banner: { textAlign: 'center', fontSize: 16, fontWeight: '700', paddingVertical: 8, borderRadius: 8 },
  badge: { alignSelf: 'flex-start', minHeight: MIN_TOUCH, justifyContent: 'center', paddingHorizontal: 14, borderRadius: 24 },
  badgeText: { fontSize: 15, fontWeight: '700' },
  top: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 8 },
  speedBox: { flexDirection: 'row', alignItems: 'flex-end', gap: 8 },
  speed: { fontSize: 112, fontWeight: '800', lineHeight: 120, fontVariant: ['tabular-nums'] },
  unit: { fontSize: 24, paddingBottom: 18 },
  limit: { width: 96, height: 96, borderRadius: 48, borderWidth: 8, alignItems: 'center', justifyContent: 'center' },
  limitText: { fontSize: 38, fontWeight: '800' },
  warnings: { flex: 1, gap: 8, justifyContent: 'center' },
  calm: { fontSize: 18, textAlign: 'center' },
  warning: { borderWidth: 4, borderRadius: 16, padding: 14 },
  warningTitle: { fontSize: 34, fontWeight: '800' },
  warningSub: { fontSize: 22, fontWeight: '700' },
  prompt: { borderRadius: 16, padding: 14, gap: 10 },
  promptTitle: { fontSize: 26, fontWeight: '800' },
  toast: { textAlign: 'center', fontSize: 20, fontWeight: '700', paddingVertical: 10, borderRadius: 10 },
  reports: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  row: { flexDirection: 'row', gap: 8 },
  big: { flexGrow: 1, flexBasis: '45%', minHeight: DRIVE_TOUCH, borderRadius: 16, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 10 },
  bigText: { fontSize: 24, fontWeight: '800', textAlign: 'center' },
});
