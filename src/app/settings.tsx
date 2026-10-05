import Constants from 'expo-constants';
import { Text } from 'react-native';

import { Placeholder } from '@/components/placeholder';
import { t } from '@/i18n';
import { useTheme } from '@/theme';

export default function SettingsScreen() {
  const theme = useTheme();
  return (
    <Placeholder title={t('tabs.settings')}>
      <Text style={{ color: theme.textSecondary }}>
        {t('settings.version', { version: Constants.expoConfig?.version ?? '?' })}
      </Text>
    </Placeholder>
  );
}
