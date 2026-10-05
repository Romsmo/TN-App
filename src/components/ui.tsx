import { Pressable, StyleSheet, Switch, Text, View, type PressableProps, type SwitchProps } from 'react-native';

import { Icon, type IconName } from '@/components/icon';
import { elevation, radius, type, useTheme } from '@/theme';

/** Minimum touch target in points: larger than the platform minimum of 44. */
export const MIN_TOUCH = 52;

type ButtonProps = Omit<PressableProps, 'children' | 'style'> & { label: string; kind?: 'primary' | 'plain'; icon?: IconName };

/** A full-width pill. `primary` is the one confident action; `plain` is a soft secondary. */
export function Button({ label, kind = 'primary', icon, disabled, accessibilityState, ...rest }: ButtonProps) {
  const theme = useTheme();
  const primary = kind === 'primary';
  const foreground = primary ? theme.onTint : theme.tint;
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ disabled: !!disabled, ...accessibilityState }}
      disabled={disabled}
      style={({ pressed }) => [
        styles.button,
        { backgroundColor: primary ? theme.tint : theme.tintSoft, opacity: disabled ? 0.45 : pressed ? 0.85 : 1, transform: [{ scale: pressed ? 0.985 : 1 }] },
      ]}
      {...rest}>
      {icon ? <Icon name={icon} size={20} color={foreground} /> : null}
      <Text style={[styles.buttonText, { color: foreground }]}>{label}</Text>
    </Pressable>
  );
}

/** A grouped card with an optional small caps title above it. */
export function Section({ title, children }: { title?: string; children: React.ReactNode }) {
  const theme = useTheme();
  return (
    <View style={styles.section}>
      {title ? (
        <Text accessibilityRole="header" style={[type.label, styles.sectionTitle, { color: theme.textSecondary }]}>
          {title}
        </Text>
      ) : null}
      <View style={[styles.sectionBody, elevation(theme), { backgroundColor: theme.surface }]}>{children}</View>
    </View>
  );
}

/** The app's switch: the confident blue when on, a quiet grey track when off. */
export function Toggle(props: SwitchProps) {
  const theme = useTheme();
  // `activeThumbColor` is react-native-web's (the browser preview); native ignores it
  const web = { activeThumbColor: '#FFFFFF' } as object;
  return <Switch trackColor={{ true: theme.tint, false: theme.border }} thumbColor="#FFFFFF" ios_backgroundColor={theme.border} {...web} {...props} />;
}

/** A small round badge with an icon, the leading mark of a settings row. */
export function RowIcon({ name }: { name: IconName }) {
  const theme = useTheme();
  return (
    <View style={[styles.rowIcon, { backgroundColor: theme.tintSoft }]}>
      <Icon name={name} size={18} color={theme.tint} />
    </View>
  );
}

export function Body({ children, secondary }: { children: React.ReactNode; secondary?: boolean }) {
  const theme = useTheme();
  return <Text style={[type.body, { color: secondary ? theme.textSecondary : theme.text }]}>{children}</Text>;
}

const styles = StyleSheet.create({
  button: { minHeight: MIN_TOUCH, borderRadius: radius.pill, paddingHorizontal: 20, paddingVertical: 10, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8 },
  buttonText: { fontSize: 17, fontWeight: '700', textAlign: 'center', flexShrink: 1 },
  section: { gap: 8 },
  sectionTitle: { marginLeft: 8 },
  rowIcon: { width: 32, height: 32, borderRadius: 16, alignItems: 'center', justifyContent: 'center' },
  sectionBody: { borderRadius: radius.lg, padding: 18, gap: 12 },
});
