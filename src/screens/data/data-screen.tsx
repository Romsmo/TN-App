import { useEffect, useState } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';

import { Body, Button, RowIcon, Section, Toggle } from '@/components/ui';
import { formatBytes } from '@/i18n/format';
import { t } from '@/i18n';
import { settingsStore, useSettings } from '@/settings';
import { useTn } from '@/state/tn-provider';
import type { BootstrapPlan } from '@/tn/types';
import type { TnService } from '@/tn/service';
import { TAB_BAR_CLEARANCE, useTheme } from '@/theme';

/** The download plan from the library; null while unknown (no service, offline, no access). Re-reads when `version` moves. */
function usePlan(service: TnService | null, version: number): BootstrapPlan | null {
  const [result, setResult] = useState<{ service: TnService; plan: BootstrapPlan | null } | null>(null);
  useEffect(() => {
    if (!service) return;
    let cancelled = false;
    service
      .planBootstrap()
      .then((plan) => !cancelled && setResult({ service, plan }))
      .catch(() => !cancelled && setResult({ service, plan: null }));
    return () => {
      cancelled = true;
    };
  }, [service, version]);
  return service && result?.service === service ? result.plan : null;
}

export function DataScreen() {
  const theme = useTheme();
  const { dataWifiOnly } = useSettings();
  const tn = useTn();
  const [reloads, setReloads] = useState(0);
  const plan = usePlan(tn.service, tn.dataVersion + reloads);

  const load = async (ignoreWifi: boolean) => {
    await tn.syncNow({ ignoreWifi });
    setReloads((n) => n + 1);
  };

  return (
    <ScrollView style={{ backgroundColor: theme.background }} contentContainerStyle={styles.content}>
      <Section>
        <View style={styles.switchRow}>
          <RowIcon name="wifi" color="#007AFF" />
          <View style={styles.flex}>
            <Body>{t('data.wifiOnly')}</Body>
          </View>
          <Toggle
            accessibilityLabel={t('data.wifiOnly')}
            value={dataWifiOnly}
            onValueChange={(value) => settingsStore.update({ dataWifiOnly: value })}
          />
        </View>
        <Body secondary>{t('data.wifiOnlyHint')}</Body>
      </Section>

      <Section>
        {plan === null ? (
          <Body secondary>{t('data.unknown')}</Body>
        ) : plan.bytesPending === 0 ? (
          <Body>{t('data.complete')}</Body>
        ) : (
          <Body>{t('data.pending', { size: formatBytes(plan.bytesPending) })}</Body>
        )}
        {tn.sync?.storageBytes != null ? <Body secondary>{t('data.stored', { size: formatBytes(tn.sync.storageBytes) })}</Body> : null}
        {plan && plan.bytesPending > 0 ? (
          <>
            <Button label={t('data.loadNow')} onPress={() => void load(false)} />
            {tn.waitingForWifi ? <Button kind="plain" label={t('data.loadAnyway')} onPress={() => void load(true)} /> : null}
          </>
        ) : null}
        <Body secondary>{t('data.regionNote')}</Body>
      </Section>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, paddingBottom: TAB_BAR_CLEARANCE + 16, gap: 18 },
  switchRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  flex: { flex: 1 },
});
