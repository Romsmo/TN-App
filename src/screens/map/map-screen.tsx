import type { CameraRef } from '@maplibre/maplibre-react-native';
import * as Location from 'expo-location';
import { useEffect, useMemo, useRef, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { Button } from '@/components/ui';
import { interimCatalog } from '@/report/catalog';
import { pendingText, rejectedText } from '@/report/pending';
import { submitHazard, voteOnReport } from '@/report/submit';
import { MAP_ATTRIBUTION, MAP_STYLE_URL } from '@/config';
import { t } from '@/i18n';
import { hazardTypesIn, toMapData } from '@/map/geojson';
import { settingsStore, useSettings } from '@/settings';
import { useTn, type TnState } from '@/state/tn-provider';
import { useTheme } from '@/theme';

import { DetailCard, type VoteState } from './detail-card';
import { FilterBar } from './filter-bar';
import { MapView } from './map-view';
import { ReportSheet, type ReportLocation } from './report-sheet';
import { useNearby, type Viewport } from './use-nearby';

type Position = { lat: number; lng: number };

/** The device position, or null without permission. `ask` shows the system dialog; without it a refused or undecided permission stays silent. */
async function currentPosition(ask: boolean): Promise<Position | null> {
  const permission = ask ? await Location.requestForegroundPermissionsAsync() : await Location.getForegroundPermissionsAsync();
  if (!permission.granted) return null;
  const { coords } = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
  return { lat: coords.latitude, lng: coords.longitude };
}

function bannerText(tn: TnState): string | null {
  if (tn.phase === 'starting') return t('status.starting');
  if (tn.phase === 'noCredentials') return t('status.noCredentials');
  if (tn.phase === 'error') return t('status.error', { message: tn.error ?? t('common.unknown') });
  if (tn.waitingForWifi) return t('status.waitingForWifi');
  if (tn.sync?.connection === 'offline') return t('status.offline');
  return null;
}

export function MapScreen() {
  const theme = useTheme();
  const tn = useTn();
  const { hiddenHazardTypes } = useSettings();
  const cameraRef = useRef<CameraRef | null>(null);

  const [viewport, setViewport] = useState<Viewport | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [located, setLocated] = useState(false);
  const [devicePosition, setDevicePosition] = useState<Position | null>(null);
  const [reporting, setReporting] = useState(false);
  const [locating, setLocating] = useState(false);
  const [draft, setDraft] = useState<Position | null>(null);
  const [reportMessage, setReportMessage] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [vote, setVote] = useState<{ id: string; state: VoteState } | null>(null);
  // Local writes show up at once (optimistic view), before any sync reports a change.
  const [localChanges, setLocalChanges] = useState(0);

  const items = useNearby(tn.service, viewport, tn.dataVersion + localChanges);
  const data = useMemo(() => toMapData(items, { hiddenHazardTypes: new Set(hiddenHazardTypes) }), [items, hiddenHazardTypes]);
  // Types seen in the data plus the ones switched off, so a hidden type can always be switched back on.
  const filterTypes = useMemo(() => [...new Set([...hazardTypesIn(items), ...hiddenHazardTypes])].sort(), [items, hiddenHazardTypes]);
  const selected = useMemo(() => {
    const item = items.find((i) => i.kind === 'hazard' && i.id === selectedId);
    return item?.kind === 'hazard' ? item : null;
  }, [items, selectedId]);

  const service = tn.service;
  const moveTo = (position: Position) => {
    setLocated(true);
    setDevicePosition(position);
    cameraRef.current?.flyTo({ center: [position.lng, position.lat], zoom: 12, duration: 800 });
    // Tells the library which tiles to watch: the one place this screen sends a (coarse) position to the library.
    void service?.updatePosition(position.lat, position.lng).catch(() => undefined);
  };
  const locate = (ask: boolean) =>
    currentPosition(ask)
      .then((position) => position && moveTo(position))
      .catch(() => undefined);

  useEffect(() => {
    // Silently, and only if the permission was granted before.
    currentPosition(false)
      .then((position) => {
        if (!position) return;
        setLocated(true);
        setDevicePosition(position);
        cameraRef.current?.flyTo({ center: [position.lng, position.lat], zoom: 12, duration: 800 });
        void service?.updatePosition(position.lat, position.lng).catch(() => undefined);
      })
      .catch(() => undefined);
  }, [service]);

  const openReport = () => {
    setReporting(true);
    setSelectedId(null);
    setReportMessage(null);
    setNotice(null);
    if (!devicePosition) {
      setLocating(true);
      currentPosition(true)
        .then((position) => position && moveTo(position))
        .catch(() => undefined)
        .finally(() => setLocating(false));
    }
  };
  const closeReport = () => {
    setReporting(false);
    setDraft(null);
    setReportMessage(null);
  };
  const reportLocation: ReportLocation = draft ? { ...draft, source: 'map' } : devicePosition ? { ...devicePosition, source: 'device' } : null;

  const pickType = async (type: string) => {
    if (!service || !reportLocation) return;
    const outcome = await submitHazard(service, type, reportLocation);
    if (!outcome.ok) {
      setReportMessage(t(`report.error.${outcome.reason}`));
      return;
    }
    closeReport();
    setNotice(t('report.saved'));
    setLocalChanges((n) => n + 1);
    void tn.syncNow(); // sends right away when allowed; otherwise the pending note explains the wait
  };

  const castVote = async (stillThere: boolean) => {
    if (!service || !selected) return;
    const outcome = await voteOnReport(service, selected.id, stillThere);
    setVote({ id: selected.id, state: outcome.ok ? 'saved' : 'failed' });
    if (outcome.ok) {
      setLocalChanges((n) => n + 1);
      void tn.syncNow();
    }
  };

  const onMapPress = (position: Position) => {
    if (reporting) setDraft(position);
    else setSelectedId(null);
  };

  const toggleType = (type: string) => {
    const hidden = new Set(hiddenHazardTypes);
    if (hidden.has(type)) hidden.delete(type);
    else hidden.add(type);
    settingsStore.update({ hiddenHazardTypes: [...hidden] });
  };

  const banner = bannerText(tn);
  const pending = pendingText({ pending: tn.sync?.pendingWrites ?? 0, waitingForWifi: tn.waitingForWifi, offline: tn.sync?.connection === 'offline' });
  const rejected = rejectedText(tn.rejectedWrites);

  return (
    <View style={[styles.screen, { backgroundColor: theme.background }]}>
      <FilterBar types={filterTypes} hidden={hiddenHazardTypes} onToggle={toggleType} />
      {banner ? (
        <Text accessibilityRole="alert" style={[styles.banner, { backgroundColor: theme.surface, color: theme.textSecondary }]}>
          {banner}
        </Text>
      ) : null}
      {pending ? <Text style={[styles.banner, { backgroundColor: theme.surface, color: theme.text }]}>{pending}</Text> : null}
      {rejected ? (
        <View style={[styles.rejected, { backgroundColor: theme.surface }]}>
          <Text style={[styles.rejectedText, { color: theme.text }]}>{rejected}</Text>
          <Button kind="plain" label={t('rejected.dismiss')} onPress={tn.dismissRejected} />
        </View>
      ) : null}
      {notice ? <Text accessibilityRole="alert" style={[styles.banner, { backgroundColor: theme.surface, color: theme.text }]}>{notice}</Text> : null}
      {!MAP_STYLE_URL ? <Text style={[styles.note, { color: theme.textSecondary }]}>{t('map.noBackground')}</Text> : null}
      <View style={styles.mapBox}>
        <MapView
          data={data}
          background={theme.surface}
          showUserLocation={located}
          onViewport={setViewport}
          onSelectHazard={(id) => {
            if (!reporting) setSelectedId(id);
          }}
          onMapPress={onMapPress}
          draft={reporting ? draft : null}
          cameraRef={cameraRef}
        />
        <Text accessibilityLabel={MAP_ATTRIBUTION} style={[styles.attribution, { backgroundColor: theme.surface, color: theme.textSecondary }]}>
          {t('map.attribution')}
        </Text>
        {!reporting ? (
          <View style={styles.locate}>
            <Button label={t('map.locate')} onPress={() => void locate(true)} />
            <Button label={t('report.open')} onPress={openReport} />
          </View>
        ) : null}
        {selected && !reporting ? (
          <View style={styles.card}>
            <DetailCard
              item={selected}
              onClose={() => setSelectedId(null)}
              onVote={(stillThere) => void castVote(stillThere)}
              voteState={vote?.id === selected.id ? vote.state : 'idle'}
            />
          </View>
        ) : null}
        {reporting ? (
          <View style={styles.card}>
            <ReportSheet
              types={interimCatalog.types()}
              location={reportLocation}
              locating={locating}
              message={reportMessage}
              onPick={(type) => void pickType(type)}
              onCancel={closeReport}
            />
          </View>
        ) : null}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1 },
  banner: { paddingHorizontal: 14, paddingVertical: 8, fontSize: 14 },
  note: { paddingHorizontal: 14, paddingVertical: 4, fontSize: 13 },
  mapBox: { flex: 1 },
  attribution: { position: 'absolute', left: 8, bottom: 8, paddingHorizontal: 6, paddingVertical: 2, fontSize: 11, borderRadius: 4, opacity: 0.9 },
  locate: { position: 'absolute', right: 12, top: 12, gap: 8 },
  rejected: { paddingHorizontal: 14, paddingVertical: 8, gap: 4 },
  rejectedText: { fontSize: 14 },
  card: { position: 'absolute', left: 12, right: 12, bottom: 36 },
});
