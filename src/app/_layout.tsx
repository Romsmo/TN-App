import { Tabs } from 'expo-router';
import { useEffect, useMemo } from 'react';

import { DriveProvider } from '@/drive/drive-provider';
import { defineDriveLocationTask } from '@/drive/location-source';
import { t } from '@/i18n';
import { createNativeClient, credentialsStore, isOnWifi, maintenance } from '@/state/app-wiring';
import { createAppDriveHost, setDriveService } from '@/state/drive-wiring';
import { TnProvider, useTn } from '@/state/tn-provider';
import { useTheme } from '@/theme';

// The OS may wake the app for a location update: the task has to exist before any screen does.
defineDriveLocationTask();

function Tabbed() {
  const theme = useTheme();
  const tn = useTn();
  useEffect(() => {
    setDriveService(tn.service);
  }, [tn.service]);
  const host = useMemo(() => createAppDriveHost(), []);

  return (
    <DriveProvider host={host}>
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
    </DriveProvider>
  );
}

export default function RootLayout() {
  return (
    <TnProvider createClient={createNativeClient} credentialsStore={credentialsStore} isOnWifi={isOnWifi} maintenance={maintenance}>
      <Tabbed />
    </TnProvider>
  );
}
