import { Pressable, StyleSheet, Text, View } from 'react-native';

import { Button, MIN_TOUCH } from '@/components/ui';
import { formatDateTime } from '@/i18n/format';
import { t } from '@/i18n';
import { hazardLabel } from '@/map/hazard-labels';
import type { HazardItem } from '@/tn/types';
import { useTheme } from '@/theme';

export type VoteState = 'idle' | 'saved' | 'failed';

type Props = {
  item: HazardItem;
  onClose: () => void;
  /** Votes "still there" (`true`) or "gone" (`false`). Without it the card has no voting (read-only). */
  onVote?: (stillThere: boolean) => void;
  voteState?: VoteState;
};

/** Details of one report: kind, how sure the community is, how long it stays. */
export function DetailCard({ item, onClose, onVote, voteState = 'idle' }: Props) {
  const theme = useTheme();
  return (
    <View accessibilityViewIsModal style={[styles.card, { backgroundColor: theme.surface }]}>
      <View style={styles.header}>
        <Text accessibilityRole="header" style={[styles.title, { color: theme.text }]}>
          {hazardLabel(item.hazardType)}
        </Text>
        <Pressable accessibilityRole="button" accessibilityLabel={t('detail.close')} onPress={onClose} style={styles.close}>
          <Text style={[styles.closeText, { color: theme.tint }]}>{t('detail.close')}</Text>
        </Pressable>
      </View>
      <Text style={[styles.line, { color: theme.text }]}>
        {t('detail.confirmed', { count: item.confirmCount })} · {t('detail.denied', { count: item.denyCount })}
      </Text>
      <Text style={[styles.line, { color: theme.textSecondary }]}>{t('detail.validUntil', { time: formatDateTime(item.expiresAt) })}</Text>
      <Text style={[styles.line, { color: theme.textSecondary }]}>{t('detail.distance', { meters: Math.round(item.distanceMeters) })}</Text>
      {item.pending ? <Text style={[styles.line, { color: theme.textSecondary }]}>{t('detail.pending')}</Text> : null}
      {onVote && !item.pending ? (
        <View style={styles.vote}>
          <Text style={[styles.line, { color: theme.text }]}>{t('vote.question')}</Text>
          {voteState === 'saved' ? (
            <Text accessibilityRole="alert" style={[styles.line, { color: theme.textSecondary }]}>
              {t('vote.thanks')}
            </Text>
          ) : (
            <View style={styles.voteRow}>
              <View style={styles.voteButton}>
                <Button label={t('vote.still')} onPress={() => onVote(true)} />
              </View>
              <View style={styles.voteButton}>
                <Button kind="plain" label={t('vote.gone')} onPress={() => onVote(false)} />
              </View>
            </View>
          )}
          {voteState === 'failed' ? (
            <Text accessibilityRole="alert" style={[styles.line, { color: theme.danger }]}>
              {t('vote.error')}
            </Text>
          ) : null}
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  card: { borderRadius: 14, padding: 14, gap: 4 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  title: { fontSize: 20, fontWeight: '600', flexShrink: 1 },
  close: { minHeight: MIN_TOUCH, minWidth: MIN_TOUCH, alignItems: 'center', justifyContent: 'center' },
  closeText: { fontSize: 16, fontWeight: '600' },
  line: { fontSize: 15 },
  vote: { gap: 6, marginTop: 8 },
  voteRow: { flexDirection: 'row', gap: 8 },
  voteButton: { flex: 1 },
});
