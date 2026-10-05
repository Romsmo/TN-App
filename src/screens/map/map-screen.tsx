import type { CameraRef } from '@maplibre/maplibre-react-native';
import * as Location from 'expo-location';
import { useEffect, useMemo, useRef, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Icon, type IconName } from '@/components/icon';
import { Button } from '@/components/ui';
import { interimCatalog } from '@/report/catalog';
import { pendingText, rejectedText } from '@/report/pending';
import { submitHazard, voteOnReport } from '@/report/submit';
import { MAP_ATTRIBUTION, MAP_STYLE_URL } from '@/config';
import { t } from '@/i18n';
import { hazardTypesIn, toMapData } from '@/map/geojson';
import { settingsStore, useSettings } from '@/settings';
import { useTn, type TnState } from '@/state/tn-provider';
import { elevation, radius, TAB_BAR_CLEARANCE, type, useTheme } from '@/theme';

import { DetailCard, type VoteState } from './detail-card';
import { FilterBar } from './filter-bar';
import { MapView } from './map-view';
import { ReportList } from './report-list';
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
  const insets = useSafeAreaInsets();
  const tn = useTn();
  const { hiddenHazardTypes } = useSettings();
  const cameraRef = useRef<CameraRef | null>(null);

  const [viewport, setViewport] = useState<Viewport | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [located, setLocated] = useState(false);
  const [listMode, setListMode] = useState(false);
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
  const visibleHazards = useMemo(
    () => items.filter((i): i is Extract<typeof i, { kind: 'hazard' }> => i.kind === 'hazard' && !hiddenHazardTypes.includes(i.hazardType)),
    [items, hiddenHazardTypes],
  );
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

  // A confirmation is a moment, not a fixture: it fades away on its own.
  useEffect(() => {
    if (!notice) return;
    const timer = setTimeout(() => setNotice(null), 6000);
    return () => clearTimeout(timer);
  }, [notice]);

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

  const notes: { key: string; text: string; tone?: 'warn' | 'ok'; icon: IconName }[] = [];
  if (banner) notes.push({ key: 'banner', text: banner, icon: 'information-circle' });
  if (pending) notes.push({ key: 'pending', text: pending, tone: 'warn', icon: 'time' });
  if (notice) notes.push({ key: 'notice', text: notice, tone: 'ok', icon: 'checkmark-circle' });
  if (!MAP_STYLE_URL) notes.push({ key: 'nomap', text: t('map.noBackground'), icon: 'map-outline' });

  const detail =
    selected && !reporting ? (
      <DetailCard item={selected} onClose={() => setSelectedId(null)} onVote={(stillThere) => void castVote(stillThere)} voteState={vote?.id === selected.id ? vote.state : 'idle'} />
    ) : null;

  return (
    <View style={[styles.screen, { backgroundColor: theme.background }]}>
      <View style={[styles.mapBox, listMode ? styles.hidden : null]}>
        <MapView
          data={data}
          background={theme.surfaceAlt}
          showUserLocation={located}
          onViewport={setViewport}
          onSelectHazard={(id) => {
            if (!reporting) setSelectedId(id);
          }}
          onMapPress={onMapPress}
          draft={reporting ? draft : null}
          cameraRef={cameraRef}
        />
      </View>

      {listMode ? (
        <ScrollView contentContainerStyle={styles.listContent}>
          <ReportList items={visibleHazards} onSelect={setSelectedId} />
        </ScrollView>
      ) : null}

      {/* floating layer on top of the map */}
      <View pointerEvents="box-none" style={styles.overlay}>
        <View pointerEvents="box-none" style={[styles.top, { paddingTop: insets.top + 8 }]}>
          <FilterBar types={filterTypes} hidden={hiddenHazardTypes} onToggle={toggleType} />
          {notes.map((note) => (
            <View key={note.key} accessibilityRole="alert" style={[styles.note, styles.noteRow, elevation(theme), { backgroundColor: theme.surface }]}>
              <Icon name={note.icon} size={18} color={note.tone === 'warn' ? theme.warn : note.tone === 'ok' ? theme.success : theme.textSecondary} />
              <Text style={[type.caption, styles.noteText, { color: note.tone === 'warn' ? theme.warn : theme.textSecondary }]}>{note.text}</Text>
            </View>
          ))}
          {rejected ? (
            <View style={[styles.note, elevation(theme), { backgroundColor: theme.surface }]}>
              <Text style={[type.caption, { color: theme.text }]}>{rejected}</Text>
              <Button kind="plain" label={t('rejected.dismiss')} onPress={tn.dismissRejected} />
            </View>
          ) : null}
        </View>

        <View pointerEvents="box-none" style={styles.bottom}>
          {!reporting ? (
            <View style={styles.fabs}>
              <Pressable
                accessibilityRole="button"
                accessibilityLabel={listMode ? t('map.showMap') : t('map.list')}
                onPress={() => setListMode((v) => !v)}
                style={[styles.fabRound, elevation(theme, 2), { backgroundColor: theme.surface }]}>
                <Icon name={listMode ? 'map' : 'list'} size={24} color={theme.tint} />
              </Pressable>
              <Pressable accessibilityRole="button" accessibilityLabel={t('map.locate')} onPress={() => void locate(true)} style={[styles.fabRound, elevation(theme, 2), { backgroundColor: theme.surface }]}>
                <Icon name="locate" size={24} color={theme.tint} />
              </Pressable>
              <Pressable accessibilityRole="button" accessibilityLabel={t('report.open')} onPress={openReport} style={[styles.fabReport, elevation(theme, 2), { backgroundColor: theme.tint }]}>
                <Icon name="add" size={26} color={theme.onTint} />
                <Text style={[styles.fabReportText, { color: theme.onTint }]}>{t('report.open')}</Text>
              </Pressable>
            </View>
          ) : null}
          {detail}
          {reporting ? (
            <ReportSheet
              types={interimCatalog.types()}
              location={reportLocation}
              locating={locating}
              message={reportMessage}
              onPick={(reportType) => void pickType(reportType)}
              onCancel={closeReport}
            />
          ) : null}
          <Text accessibilityLabel={MAP_ATTRIBUTION} style={[styles.attribution, { color: theme.textSecondary }]}>
            {t('map.attribution')}
          </Text>
        </View>
      </View>
    </View>
  );
}

const FILL = { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 } as const;

const styles = StyleSheet.create({
  screen: { flex: 1 },
  mapBox: { ...FILL },
  hidden: { display: 'none' },
  listContent: { paddingTop: 190, paddingBottom: TAB_BAR_CLEARANCE + 16 },
  overlay: { ...FILL, justifyContent: 'space-between' },
  top: { gap: 8 },
  note: { marginHorizontal: 16, borderRadius: radius.md, paddingHorizontal: 14, paddingVertical: 10, gap: 6 },
  noteRow: { flexDirection: 'row', alignItems: 'center', gap: 10, alignSelf: 'flex-start' },
  noteText: { flexShrink: 1 },
  bottom: { gap: 10, paddingHorizontal: 16, paddingBottom: TAB_BAR_CLEARANCE },
  fabs: { alignItems: 'flex-end', gap: 12 },
  fabRound: { width: 52, height: 52, borderRadius: 26, alignItems: 'center', justifyContent: 'center' },
  fabReport: { height: 56, borderRadius: 28, paddingHorizontal: 20, flexDirection: 'row', alignItems: 'center', gap: 6 },
  fabReportText: { fontSize: 17, fontWeight: '800' },
  attribution: { fontSize: 11, alignSelf: 'flex-start', marginLeft: 4 },
});
