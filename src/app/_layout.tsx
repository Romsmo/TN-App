import { Tabs } from 'expo-router';

import { t } from '@/i18n';
import { createNativeClient, credentialsStore, isOnWifi } from '@/state/app-wiring';
import { TnProvider } from '@/state/tn-provider';
import { useTheme } from '@/theme';


export default function RootLayout() {
  const theme = useTheme();
  return (
    <TnProvider createClient={createNativeClient} credentialsStore={credentialsStore} isOnWifi={isOnWifi}>
      <Tabs
        screenOptions={{
          tabBarActiveTintColor: theme.tint,
          tabBarStyle: { backgroundColor: theme.surface },
          headerStyle: { backgroundColor: theme.surface },
          headerTintColor: theme.text,
        }}>
        <Tabs.Screen name="index" options={{ title: t('tabs.map') }} />
        <Tabs.Screen name="drive" options={{ title: t('tabs.drive') }} />
        <Tabs.Screen name="settings" options={{ title: t('tabs.settings') }} />
        <Tabs.Screen name="server" options={{ href: null, title: t('server.title') }} />
        <Tabs.Screen name="data" options={{ href: null, title: t('data.title') }} />
        <Tabs.Screen name="info" options={{ href: null, title: t('info.title') }} />
      </Tabs>
    </TnProvider>
  );
}
