import { Pressable, StyleSheet, Text, View } from 'react-native';

import { Icon } from '@/components/icon';
import { Button, MIN_TOUCH } from '@/components/ui';
import { formatDateTime } from '@/i18n/format';
import { t } from '@/i18n';
import { hazardColor } from '@/map/colors';
import { hazardIcon } from '@/map/hazard-icons';
import { hazardLabel } from '@/map/hazard-labels';
import type { HazardItem } from '@/tn/types';
import { elevation, radius, type, useTheme } from '@/theme';

export type VoteState = 'idle' | 'saved' | 'failed';

type Props = {
  item: HazardItem;
  onClose: () => void;
  /** Votes "still there" (`true`) or "gone" (`false`). Without it the card has no voting (read-only). */
  onVote?: (stillThere: boolean) => void;
  voteState?: VoteState;
};

/** A bottom sheet with the details of one report: kind, how sure the community is, how long it stays. */
export function DetailCard({ item, onClose, onVote, voteState = 'idle' }: Props) {
  const theme = useTheme();
  const color = hazardColor(item.hazardType);
  return (
    <View accessibilityViewIsModal style={[styles.card, elevation(theme, 2), { backgroundColor: theme.surface }]}>
      <View style={[styles.grabber, { backgroundColor: theme.border }]} />
      <View style={styles.header}>
        <View style={[styles.badge, { backgroundColor: color }]}>
          <Icon name={hazardIcon(item.hazardType)} size={24} color="#FFFFFF" />
        </View>
        <Text accessibilityRole="header" style={[type.heading, styles.title, { color: theme.text }]}>
          {hazardLabel(item.hazardType)}
        </Text>
        <Pressable accessibilityRole="button" accessibilityLabel={t('detail.close')} onPress={onClose} style={[styles.close, { backgroundColor: theme.surfaceAlt }]}>
          <Icon name="close" size={20} color={theme.text} />
        </Pressable>
      </View>
      <Text style={[type.body, { color: theme.text }]}>
        {t('detail.confirmed', { count: item.confirmCount })} · {t('detail.denied', { count: item.denyCount })}
      </Text>
      <Text style={[type.caption, { color: theme.textSecondary }]}>{t('detail.validUntil', { time: formatDateTime(item.expiresAt) })}</Text>
      <Text style={[type.caption, { color: theme.textSecondary }]}>{t('detail.distance', { meters: Math.round(item.distanceMeters) })}</Text>
      {item.pending ? <Text style={[type.caption, { color: theme.warn }]}>{t('detail.pending')}</Text> : null}
      {onVote && !item.pending ? (
        <View style={styles.vote}>
          <Text style={[styles.question, { color: theme.text }]}>{t('vote.question')}</Text>
          {voteState === 'saved' ? (
            <Text accessibilityRole="alert" style={[type.body, { color: theme.success }]}>
              {t('vote.thanks')}
            </Text>
          ) : (
            <View style={styles.voteRow}>
              <View style={styles.voteButton}>
                <Button icon="checkmark-circle" label={t('vote.still')} onPress={() => onVote(true)} />
              </View>
              <View style={styles.voteButton}>
                <Button kind="plain" icon="close-circle" label={t('vote.gone')} onPress={() => onVote(false)} />
              </View>
            </View>
          )}
          {voteState === 'failed' ? (
            <Text accessibilityRole="alert" style={[type.caption, { color: theme.danger }]}>
              {t('vote.error')}
            </Text>
          ) : null}
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  card: { borderRadius: radius.sheet, padding: 18, paddingTop: 10, gap: 6 },
  grabber: { alignSelf: 'center', width: 40, height: 5, borderRadius: 3, marginBottom: 8 },
  header: { flexDirection: 'row', alignItems: 'center', gap: 12, marginBottom: 4 },
  badge: { width: 44, height: 44, borderRadius: 22, alignItems: 'center', justifyContent: 'center' },
  title: { flex: 1 },
  close: { width: MIN_TOUCH - 8, height: MIN_TOUCH - 8, borderRadius: (MIN_TOUCH - 8) / 2, alignItems: 'center', justifyContent: 'center' },
  vote: { gap: 8, marginTop: 10 },
  question: { fontSize: 15, fontWeight: '700' },
  voteRow: { flexDirection: 'row', gap: 8 },
  voteButton: { flex: 1 },
});
