import { Modal, ScrollView, StyleSheet, Text, View } from 'react-native';

import { Button } from '@/components/ui';
import type { Segment } from '@/legal/texts';
import { elevation, radius, type, useTheme } from '@/theme';

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
      <View style={[styles.backdrop, { backgroundColor: theme.overlay }]}>
        <View accessibilityRole="alert" style={[styles.card, elevation(theme, 2), { backgroundColor: theme.surface }]}>
          <Text accessibilityRole="header" style={[type.heading, { color: theme.text }]}>
            {title}
          </Text>
          <ScrollView style={styles.scroll}>
            <Text style={[type.body, { color: theme.text }]}>{renderBody(body)}</Text>
          </ScrollView>
          <View style={styles.buttons}>
            <Button label={confirmLabel} onPress={onConfirm} />
            {cancelLabel && onCancel ? <Button kind="plain" label={cancelLabel} onPress={onCancel} /> : null}
          </View>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, justifyContent: 'center', padding: 20 },
  card: { borderRadius: radius.sheet, padding: 22, gap: 14, maxHeight: '85%' },
  scroll: { flexGrow: 0 },
  buttons: { gap: 8 },
  strong: { fontWeight: '800' },
});
