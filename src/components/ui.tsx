import { Children, isValidElement } from 'react';
import { Pressable, StyleSheet, Switch, Text, View, type PressableProps, type SwitchProps } from 'react-native';

import { Icon, type IconName } from '@/components/icon';
import { elevation, radius, squircle, type, useTheme } from '@/theme';

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
      <View style={[styles.sectionBody, squircle, elevation(theme), { backgroundColor: theme.surface }]}>{children}</View>
    </View>
  );
}

/** The app's switch, in the system look: green track when on, grey when off, white thumb. */
export function Toggle(props: SwitchProps) {
  const theme = useTheme();
  const on = theme.background === '#000000' ? '#30D158' : '#34C759';
  // `activeThumbColor` is react-native-web's (the browser preview); native ignores it
  const web = { activeThumbColor: '#FFFFFF' } as object;
  return <Switch trackColor={{ true: on, false: theme.surfaceAlt }} thumbColor="#FFFFFF" ios_backgroundColor={theme.surfaceAlt} {...web} {...props} />;
}

/**
 * An inset grouped list, as in the iOS Settings app: one rounded surface, rows separated by hairlines that start after
 * the leading icon. Every child is one row.
 */
export function Group({ title, footer, children }: { title?: string; footer?: string; children: React.ReactNode }) {
  const theme = useTheme();
  const rows = Children.toArray(children).filter(isValidElement);
  return (
    <View style={styles.group}>
      {title ? (
        <Text accessibilityRole="header" style={[type.label, styles.groupTitle, { color: theme.textSecondary }]}>
          {title}
        </Text>
      ) : null}
      <View style={[styles.groupBody, squircle, { backgroundColor: theme.surface }]}>
        {rows.map((row, index) => (
          <View key={row.key ?? index} style={[styles.cell, index > 0 ? { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: theme.border } : null]}>
            {row}
          </View>
        ))}
      </View>
      {footer ? <Text style={[type.caption, styles.groupFooter, { color: theme.textSecondary }]}>{footer}</Text> : null}
    </View>
  );
}

/** iOS-style segmented control: a grey track with a raised white (dark: lighter grey) segment for the selection. */
export function Segmented<T extends string | number>({ label, options, value, onChange }: { label: string; options: { value: T; label: string }[]; value: T; onChange: (v: T) => void }) {
  const theme = useTheme();
  const dark = theme.background === '#000000';
  return (
    <View accessibilityRole="radiogroup" accessibilityLabel={label} style={[styles.segmented, { backgroundColor: theme.surfaceAlt }]}>
      {options.map((o) => {
        const selected = o.value === value;
        return (
          <Pressable
            key={String(o.value)}
            accessibilityRole="button"
            accessibilityLabel={o.label}
            accessibilityState={{ selected }}
            onPress={() => onChange(o.value)}
            style={[styles.segment, selected ? [elevation(theme), { backgroundColor: dark ? '#636366' : '#FFFFFF' }] : null]}>
            <Text style={[styles.segmentText, { color: theme.text, fontWeight: selected ? '700' : '500' }]}>{o.label}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

/** The big screen title of the iOS design; it scrolls away with the content. */
export function LargeTitle({ children }: { children: string }) {
  const theme = useTheme();
  return (
    <Text accessibilityRole="header" style={[type.title, styles.largeTitle, { color: theme.text }]}>
      {children}
    </Text>
  );
}

/** The leading mark of a settings row: a coloured rounded square with a white glyph, as in iOS Settings. */
export function RowIcon({ name, color }: { name: IconName; color?: string }) {
  const theme = useTheme();
  return (
    <View style={[styles.rowIcon, squircle, { backgroundColor: color ?? theme.tint }]}>
      <Icon name={name} size={18} color="#FFFFFF" />
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
  rowIcon: { width: 30, height: 30, borderRadius: 8, alignItems: 'center', justifyContent: 'center' },
  group: { gap: 6 },
  groupTitle: { marginLeft: 16 },
  groupBody: { borderRadius: radius.md, overflow: 'hidden' },
  groupFooter: { marginHorizontal: 16 },
  cell: { paddingHorizontal: 16, paddingVertical: 11, minHeight: 48, justifyContent: 'center', gap: 6 },
  segmented: { flexDirection: 'row', borderRadius: 10, padding: 2 },
  segment: { flex: 1, minHeight: 36, borderRadius: 8, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 8, ...squircle },
  segmentText: { fontSize: 15 },
  largeTitle: { marginBottom: 4 },
  sectionBody: { borderRadius: radius.md, padding: 16, gap: 12 },
});
