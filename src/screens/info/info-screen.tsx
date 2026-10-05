import * as Linking from 'expo-linking';
import { Image, ScrollView, StyleSheet, useColorScheme, View } from 'react-native';

import { Body, Button, Section } from '@/components/ui';
import { SOURCE_REPO_URL } from '@/config';
import { renderBody } from '@/components/confirm-dialog';
import { getLanguage, t } from '@/i18n';
import { LICENSES } from '@/legal/licenses';
import { CAMERA_NOTICE } from '@/legal/texts';
import { TAB_BAR_CLEARANCE, useTheme } from '@/theme';

/** Library version shown for transparency; passed in so this screen never imports native code. */
export function InfoScreen({ libraryVersion }: { libraryVersion: string }) {
  const theme = useTheme();
  const dark = useColorScheme() === 'dark';
  return (
    <ScrollView style={{ backgroundColor: theme.background }} contentContainerStyle={styles.content}>
      <View style={styles.logoBox}>
        <Image
          accessibilityLabel="Trafficnetwork"
          source={dark ? require('../../../assets/images/splash-icon-dark.png') : require('../../../assets/images/splash-icon.png')}
          style={styles.logo}
          resizeMode="contain"
        />
      </View>
      <Section>
        <Body>{t('info.osm')}</Body>
        <Body>{t('info.maplibre')}</Body>
        <Body secondary>{t('info.reports')}</Body>
      </Section>
      <Section title={t('info.cameraNotice')}>
        <Body>{renderBody(CAMERA_NOTICE[getLanguage()])}</Body>
      </Section>
      <Section>
        <Body secondary>{t('info.library', { version: libraryVersion })}</Body>
        <Body secondary>{t('info.source', { url: SOURCE_REPO_URL })}</Body>
        <Button kind="plain" label={SOURCE_REPO_URL} onPress={() => void Linking.openURL(SOURCE_REPO_URL)} />
      </Section>
      <Section title={t('info.components')}>
        {LICENSES.map((entry) => (
          <Body key={entry.name} secondary>
            {entry.name} {entry.version} — {entry.license}
          </Body>
        ))}
      </Section>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, paddingBottom: TAB_BAR_CLEARANCE + 16, gap: 18 },
  logoBox: { alignItems: 'center' },
  logo: { width: 140, height: 140 },
});
