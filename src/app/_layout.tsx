import { Tabs } from 'expo-router';

import { t } from '@/i18n';
import { useTheme } from '@/theme';

export default function RootLayout() {
  const theme = useTheme();
  return (
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
    </Tabs>
  );
}
