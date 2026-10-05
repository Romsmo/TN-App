import Constants from 'expo-constants';
import { Link } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { MIN_TOUCH, Section } from '@/components/ui';
import { t, type TextKey } from '@/i18n';
import { useTheme } from '@/theme';

type Entry = { href: '/server' | '/data' | '/info'; title: TextKey; hint: TextKey };

const ENTRIES: Entry[] = [
  { href: '/server', title: 'settings.server', hint: 'settings.serverHint' },
  { href: '/data', title: 'settings.data', hint: 'settings.dataHint' },
  { href: '/info', title: 'settings.info', hint: 'settings.infoHint' },
];

export function SettingsScreen() {
  const theme = useTheme();
  return (
    <ScrollView style={{ backgroundColor: theme.background }} contentContainerStyle={styles.content}>
      <Section>
        {ENTRIES.map((entry) => (
          <Link key={entry.href} href={entry.href} asChild>
            <Pressable accessibilityRole="link" accessibilityLabel={`${t(entry.title)}, ${t(entry.hint)}`} style={styles.entry}>
              <View>
                <Text style={[styles.title, { color: theme.text }]}>{t(entry.title)}</Text>
                <Text style={[styles.hint, { color: theme.textSecondary }]}>{t(entry.hint)}</Text>
              </View>
            </Pressable>
          </Link>
        ))}
      </Section>
      <Text style={[styles.version, { color: theme.textSecondary }]}>
        {t('settings.version', { version: Constants.expoConfig?.version ?? '?' })}
      </Text>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, gap: 18 },
  entry: { minHeight: MIN_TOUCH, justifyContent: 'center' },
  title: { fontSize: 17, fontWeight: '600' },
  hint: { fontSize: 14 },
  version: { textAlign: 'center', fontSize: 13 },
});
