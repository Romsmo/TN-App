import { Modal, ScrollView, StyleSheet, Text, View } from 'react-native';

import { Button } from '@/components/ui';
import type { Segment } from '@/legal/texts';
import { useTheme } from '@/theme';

type Props = {
  visible: boolean;
  title: string;
  /** Plain text, or segments with bold parts. */
  body: string | readonly Segment[];
  confirmLabel: string;
  /** Without a cancel label the dialog only informs (one button). */
  cancelLabel?: string;
  onConfirm: () => void;
  onCancel?: () => void;
};

export function renderBody(body: string | readonly Segment[]): React.ReactNode {
  if (typeof body === 'string') return body;
  return body.map((s, i) => (s.strong ? <Text key={i} style={styles.strong}>{s.text}</Text> : s.text));
}

/** A plain, readable dialog. Used for the legal notices: no tricks, equal weight for both buttons. */
export function ConfirmDialog({ visible, title, body, confirmLabel, cancelLabel, onConfirm, onCancel }: Props) {
  const theme = useTheme();
  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onCancel ?? onConfirm} accessibilityViewIsModal>
      <View style={styles.backdrop}>
        <View accessibilityRole="alert" style={[styles.card, { backgroundColor: theme.surface }]}>
          <Text accessibilityRole="header" style={[styles.title, { color: theme.text }]}>
            {title}
          </Text>
          <ScrollView style={styles.scroll}>
            <Text style={[styles.body, { color: theme.text }]}>{renderBody(body)}</Text>
          </ScrollView>
          <Button label={confirmLabel} onPress={onConfirm} />
          {cancelLabel && onCancel ? <Button kind="plain" label={cancelLabel} onPress={onCancel} /> : null}
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.55)', justifyContent: 'center', padding: 20 },
  card: { borderRadius: 16, padding: 18, gap: 12, maxHeight: '85%' },
  title: { fontSize: 20, fontWeight: '700' },
  scroll: { flexGrow: 0 },
  body: { fontSize: 17, lineHeight: 24 },
  strong: { fontWeight: '800' },
});
