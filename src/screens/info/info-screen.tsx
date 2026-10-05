import * as Linking from 'expo-linking';
import { ScrollView, StyleSheet } from 'react-native';

import { Body, Button, Section } from '@/components/ui';
import { SOURCE_REPO_URL } from '@/config';
import { t } from '@/i18n';
import { useTheme } from '@/theme';

/** Library version shown for transparency; passed in so this screen never imports native code. */
export function InfoScreen({ libraryVersion }: { libraryVersion: string }) {
  const theme = useTheme();
  return (
    <ScrollView style={{ backgroundColor: theme.background }} contentContainerStyle={styles.content}>
      <Section>
        <Body>{t('info.osm')}</Body>
        <Body>{t('info.maplibre')}</Body>
        <Body secondary>{t('info.reports')}</Body>
      </Section>
      <Section>
        <Body secondary>{t('info.library', { version: libraryVersion })}</Body>
        <Body secondary>{t('info.source', { url: SOURCE_REPO_URL })}</Body>
        <Button kind="plain" label={SOURCE_REPO_URL} onPress={() => void Linking.openURL(SOURCE_REPO_URL)} />
      </Section>
    </ScrollView>
  );
}

const styles = StyleSheet.create({ content: { padding: 16, gap: 18 } });
