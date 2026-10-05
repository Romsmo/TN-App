import { Pressable, StyleSheet, Text, View, type PressableProps } from 'react-native';

import { useTheme } from '@/theme';

/** Minimum touch target in points: larger than the platform minimum of 44. */
export const MIN_TOUCH = 48;

type ButtonProps = Omit<PressableProps, 'children' | 'style'> & { label: string; kind?: 'primary' | 'plain' };

export function Button({ label, kind = 'primary', disabled, ...rest }: ButtonProps) {
  const theme = useTheme();
  const primary = kind === 'primary';
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ disabled: !!disabled }}
      disabled={disabled}
      style={({ pressed }) => [
        styles.button,
        { backgroundColor: primary ? theme.tint : theme.surface, opacity: disabled ? 0.45 : pressed ? 0.8 : 1 },
      ]}
      {...rest}>
      <Text style={[styles.buttonText, { color: primary ? theme.onTint : theme.tint }]}>{label}</Text>
    </Pressable>
  );
}

export function Section({ title, children }: { title?: string; children: React.ReactNode }) {
  const theme = useTheme();
  return (
    <View style={styles.section}>
      {title ? (
        <Text accessibilityRole="header" style={[styles.sectionTitle, { color: theme.textSecondary }]}>
          {title}
        </Text>
      ) : null}
      <View style={[styles.sectionBody, { backgroundColor: theme.surface }]}>{children}</View>
    </View>
  );
}

export function Body({ children, secondary }: { children: React.ReactNode; secondary?: boolean }) {
  const theme = useTheme();
  return <Text style={[styles.body, { color: secondary ? theme.textSecondary : theme.text }]}>{children}</Text>;
}

const styles = StyleSheet.create({
  button: { minHeight: MIN_TOUCH, borderRadius: 10, paddingHorizontal: 16, alignItems: 'center', justifyContent: 'center' },
  buttonText: { fontSize: 17, fontWeight: '600' },
  section: { gap: 6 },
  sectionTitle: { fontSize: 13, textTransform: 'uppercase', marginLeft: 4 },
  sectionBody: { borderRadius: 12, padding: 14, gap: 10 },
  body: { fontSize: 16, lineHeight: 22 },
});
