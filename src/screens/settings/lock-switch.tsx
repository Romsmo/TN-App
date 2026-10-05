import { useState } from 'react';
import { StyleSheet, View } from 'react-native';

import { ConfirmDialog } from '@/components/confirm-dialog';
import { Body, RowIcon, Toggle } from '@/components/ui';
import { getLanguage, t } from '@/i18n';
import { LOCK_WARNING } from '@/legal/texts';

type Props = {
  enabled: boolean;
  onChange: (enabled: boolean) => void;
};

/**
 * The speed lock option. Switching it on needs nothing; switching it off shows the warning and needs an explicit
 * confirmation, every single time. Where the option is reachable at all is decided by the screen's LockGuard.
 */
export function LockSwitch({ enabled, onChange }: Props) {
  const [asking, setAsking] = useState(false);
  return (
    <View>
      <View style={styles.row}>
        <RowIcon name="lock-closed" color="#8E8E93" />
        <View style={styles.flex}>
          <Body>{t('lockSwitch.label')}</Body>
        </View>
        <Toggle
          accessibilityLabel={t('lockSwitch.label')}
          value={enabled}
          onValueChange={(value) => (value ? onChange(true) : setAsking(true))}
        />
      </View>
      <Body secondary>{t('lockSwitch.hint')}</Body>
      <ConfirmDialog
        visible={asking}
        title={t('lockSwitch.confirmTitle')}
        body={LOCK_WARNING[getLanguage()]}
        confirmLabel={t('lockSwitch.confirm')}
        cancelLabel={t('lockSwitch.cancel')}
        onConfirm={() => {
          setAsking(false);
          onChange(false);
        }}
        onCancel={() => setAsking(false)}
      />
    </View>
  );
}

const styles = StyleSheet.create({ row: { flexDirection: 'row', alignItems: 'center', gap: 12 }, flex: { flex: 1 } });
