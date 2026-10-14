import { useEffect, useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';

import { Body, Button, RowIcon, Section, Segmented, Toggle } from '@/components/ui';
import { formatBytes } from '@/i18n/format';
import { getLanguage, t } from '@/i18n';
import { isLeaving, LIMIT_CHOICES, loadOfflineView, regionName, toggleRegion, usedBytes, type OfflineView } from '@/offline/offline';
import { settingsStore, useSettings } from '@/settings';
import { useTn } from '@/state/tn-provider';
import type { BootstrapPlan } from '@/tn/types';
import type { TnService } from '@/tn/service';
import { TAB_BAR_CLEARANCE, type, useTheme } from '@/theme';

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

/** The offline settings, usage, regions and plan; null until read, and again when there is no service. Re-reads when `version` moves. */
function useOfflineView(service: TnService | null, version: number): OfflineView | null {
  const [result, setResult] = useState<{ service: TnService; version: number; view: OfflineView } | null>(null);
  useEffect(() => {
    if (!service) return;
    let cancelled = false;
    void loadOfflineView(service).then((view) => !cancelled && setResult({ service, version, view }));
    return () => {
      cancelled = true;
    };
  }, [service, version]);
  return service && result?.service === service && result.version === version ? result.view : null;
}

function limitLabel(maxBytes: number | null): string {
  return maxBytes === null ? t('offline.limitNone') : formatBytes(maxBytes);
}

export function DataScreen() {
  const theme = useTheme();
  const { dataWifiOnly } = useSettings();
  const tn = useTn();
  const [reloads, setReloads] = useState(0);
  const plan = usePlan(tn.service, tn.dataVersion + reloads);
  const view = useOfflineView(tn.service, tn.dataVersion + reloads);
  const settings = view?.settings ?? null;

  /** Stores the choice, then lets the next sync apply it (it respects "Wi-Fi only"). */
  const choose = async (change: (service: TnService) => Promise<unknown>) => {
    if (!tn.service) return;
    try {
      await change(tn.service);
    } catch {
      // the screen re-reads below and shows what is really stored
    }
    setReloads((n) => n + 1);
    void tn.syncNow().then(() => setReloads((n) => n + 1));
  };

  const load = async (ignoreWifi: boolean) => {
    await tn.syncNow({ ignoreWifi });
    setReloads((n) => n + 1);
  };

  return (
    <ScrollView style={{ backgroundColor: theme.background }} contentContainerStyle={styles.content}>
      {settings ? (
        <Section title={t('offline.mode')}>
          <>
            <Segmented
              label={t('offline.mode')}
              options={[
                { value: 'auto', label: t('offline.mode.auto') },
                { value: 'regions', label: t('offline.mode.regions') },
              ]}
              value={settings.mode === 'auto' ? 'auto' : 'regions'}
              onChange={(mode) => {
                if (mode === 'auto') void choose((service) => service.setOfflineRegions({ mode: 'auto' }));
              }}
            />
            <Body secondary>{settings.mode === 'auto' ? t('offline.auto.hint') : settings.mode === 'all' ? t('offline.all.hint') : t('offline.regions.hint')}</Body>
            {settings.mode === 'auto' && view?.plan?.needsLocation ? <Body>{t('status.needsLocation')}</Body> : null}
          </>
        </Section>
      ) : null}

      {view?.usage ? (
        <Section title={t('offline.storage')}>
          <Body>{t('offline.used', { size: formatBytes(usedBytes(view.usage)) })}</Body>
          <Body secondary>{t('offline.limit', { limit: limitLabel(settings?.maxBytes ?? view.usage.maxBytes) })}</Body>
          <View style={styles.chips} accessibilityRole="radiogroup" accessibilityLabel={t('offline.limitChoose')}>
            {LIMIT_CHOICES.map((choice) => {
              const selected = (settings?.maxBytes ?? null) === choice;
              return (
                <Button
                  key={String(choice)}
                  kind={selected ? 'primary' : 'plain'}
                  label={limitLabel(choice)}
                  accessibilityState={{ selected }}
                  onPress={() => void choose((service) => service.setStorageLimits({ maxBytes: choice }))}
                />
              );
            })}
          </View>
          {view.plan && !view.plan.fits ? <Body>{t('offline.doesNotFit')}</Body> : null}
        </Section>
      ) : null}

      {view ? (
      <Section title={t('offline.regions')}>
        {view.regions && settings ? (
          view.regions.length === 0 ? (
            <Body secondary>{t('offline.regions.none')}</Body>
          ) : (
            view.regions.map((region) => {
              const chosen = settings.mode === 'regions' ? settings.regions.includes(region.id) : region.selected;
              const leaving = isLeaving(region, settings);
              const state = leaving ? t('offline.region.leaving') : region.state === 'complete' ? t('offline.region.complete') : region.state === 'partial' ? t('offline.region.partial') : t('offline.region.none');
              const size = `${region.complete ? '' : t('offline.atLeast') + ' '}${formatBytes(region.estimatedDeviceBytes)}`;
              const name = regionName(region, getLanguage());
              return (
                <View key={region.id} style={styles.switchRow}>
                  <View style={styles.flex}>
                    <Body>{name}</Body>
                    <Text style={[type.caption, { color: theme.textSecondary }]}>{`${size} · ${state}`}</Text>
                  </View>
                  <Toggle
                    accessibilityLabel={t('offline.region.keep', { name })}
                    value={chosen}
                    onValueChange={() => void choose((service) => service.setOfflineRegions({ regions: toggleRegion(settings.regions, region.id) }))}
                  />
                </View>
              );
            })
          )
        ) : view.needsConnection ? (
          <Body secondary>{t('offline.needsConnection')}</Body>
        ) : (
          <Body secondary>{t('data.unknown')}</Body>
        )}
        <Body secondary>{t('offline.regions.warn')}</Body>
      </Section>
      ) : null}

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
        <Body secondary>{t('offline.onlineOnly')}</Body>
      </Section>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, paddingBottom: TAB_BAR_CLEARANCE + 16, gap: 18 },
  switchRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  chips: { gap: 8 },
  flex: { flex: 1 },
});
