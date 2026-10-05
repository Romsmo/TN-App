import { Tabs } from 'expo-router';
import { useEffect, useMemo } from 'react';
import type { ColorValue } from 'react-native';

import { Icon, type IconName } from '@/components/icon';
import { DriveProvider, useDriveSnapshot } from '@/drive/drive-provider';
import { drivePalette } from '@/drive/palette';
import { defineDriveLocationTask } from '@/drive/location-backend';
import { t } from '@/i18n';
import { createNativeClient, credentialsStore, isOnWifi, maintenance } from '@/state/app-wiring';
import { createAppDriveHost, setDriveService } from '@/state/drive-wiring';
import { TnProvider, useTn } from '@/state/tn-provider';
import { elevation, radius, useTheme } from '@/theme';

// The OS may wake the app for a location update: the task has to exist before any screen does.
defineDriveLocationTask();

const TAB_ICONS: Record<string, { on: IconName; off: IconName }> = {
  index: { on: 'map', off: 'map-outline' },
  drive: { on: 'speedometer', off: 'speedometer-outline' },
  settings: { on: 'settings', off: 'settings-outline' },
};

function TabIcon({ name, focused, color }: { name: string; focused: boolean; color: ColorValue }) {
  const icons = TAB_ICONS[name]!;
  return <Icon name={focused ? icons.on : icons.off} size={24} color={String(color)} />;
}

const tabIcon = (name: string) => {
  const render = ({ focused, color }: { focused: boolean; color: ColorValue }) => <TabIcon name={name} focused={focused} color={color} />;
  render.displayName = `TabIcon(${name})`;
  return render;
};

function TabsView() {
  const theme = useTheme();
  // While a drive is on, the whole app chrome turns dark and calm: no bright bar in the driver's face at night.
  const driving = useDriveSnapshot()?.active === true;
  const bar = driving ? drivePalette.tile : theme.surface;
  const inactive = driving ? drivePalette.textSecondary : theme.textSecondary;
  const active = driving ? drivePalette.tint : theme.tint;
  return (
    <Tabs
      screenOptions={{
        tabBarActiveTintColor: active,
        tabBarInactiveTintColor: inactive,
        tabBarShowLabel: true,
        tabBarLabelStyle: { fontSize: 12, fontWeight: '700' },
        // a floating, rounded bar: the screens leave room for it (TAB_BAR_CLEARANCE)
        tabBarStyle: {
          position: 'absolute',
          left: 16,
          right: 16,
          bottom: 14,
          height: 66,
          paddingTop: 6,
          paddingBottom: 8,
          borderRadius: radius.pill,
          borderTopWidth: 0,
          backgroundColor: bar,
          ...elevation(theme, 2),
        },
        tabBarItemStyle: { borderRadius: radius.pill },
        headerStyle: { backgroundColor: theme.background },
        headerShadowVisible: false,
        headerTintColor: theme.text,
        headerTitleAlign: 'left',
        headerTitleStyle: { fontWeight: '800', fontSize: 22, letterSpacing: -0.4 },
        sceneStyle: { backgroundColor: theme.background },
      }}>
      <Tabs.Screen name="index" options={{ title: t('tabs.map'), tabBarIcon: tabIcon('index'), headerShown: false }} />
      <Tabs.Screen
        name="drive"
        options={{ title: t('tabs.drive'), tabBarIcon: tabIcon('drive'), headerShown: false, sceneStyle: { backgroundColor: driving ? drivePalette.background : theme.background } }}
      />
      <Tabs.Screen name="settings" options={{ title: t('tabs.settings'), tabBarIcon: tabIcon('settings') }} />
      <Tabs.Screen name="server" options={{ href: null, title: t('server.title') }} />
      <Tabs.Screen name="data" options={{ href: null, title: t('data.title') }} />
      <Tabs.Screen name="info" options={{ href: null, title: t('info.title') }} />
    </Tabs>
  );
}

function Tabbed() {
  const tn = useTn();
  useEffect(() => {
    setDriveService(tn.service);
  }, [tn.service]);
  const host = useMemo(() => createAppDriveHost(), []);

  return (
    <DriveProvider host={host}>
      <TabsView />
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
