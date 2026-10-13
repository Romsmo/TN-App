import type { CameraRef } from '@maplibre/maplibre-react-native';
import type { Map as MapLibreMap, StyleSpecification } from 'maplibre-gl';
import { createElement, useEffect, useRef, useState } from 'react';
import { StyleSheet, useColorScheme, View } from 'react-native';

import { MAP_STYLE_URL, MAP_STYLE_URL_DARK } from '@/config';
import { t } from '@/i18n';
import { hazardColorExpression } from '@/map/colors';
import { appBase } from '@/web/base';

import type { MapViewProps } from './map-view';
import { radiusFor } from './use-nearby';

type MapLibre = typeof import('maplibre-gl');

const START = { center: [10, 50] as [number, number], zoom: 4 };

let loading: Promise<MapLibre> | null = null;

/**
 * The map library is not part of the app's main bundle: it is loaded when the map first shows (a plain script and its
 * stylesheet next to the app, copied by scripts/web-postbuild.mjs), so the start of the app does not wait for it.
 */
export function loadMapLibre(): Promise<MapLibre> {
  loading ??= new Promise<MapLibre>((resolve, reject) => {
    const base = `${appBase()}maplibre/`;
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = `${base}maplibre-gl.css`;
    const script = document.createElement('script');
    script.src = `${base}maplibre-gl.js`;
    script.onload = () => resolve((window as unknown as { maplibregl: MapLibre }).maplibregl);
    script.onerror = () => {
      loading = null;
      reject(new Error('The map library could not be loaded.'));
    };
    document.head.append(link, script);
  });
  return loading;
}

function plainStyle(background: string): StyleSpecification {
  return { version: 8, sources: {}, layers: [{ id: 'background', type: 'background', paint: { 'background-color': background } }] };
}

const EMPTY = { type: 'FeatureCollection', features: [] } as const;

/**
 * The browser map (maplibre-gl): the same layers as the native map — report points coloured by type, camera zones as
 * areas only, the spot picked for a report — and the same events. Drawn with WebGL; where a device cannot, the screen
 * around it (list view, reports) still works.
 */
export function MapView({ data, background, showUserLocation, userPosition, onViewport, onSelectHazard, onMapPress, draft, cameraRef }: MapViewProps) {
  const dark = useColorScheme() === 'dark';
  const styleUrl = (dark ? MAP_STYLE_URL_DARK : undefined) ?? MAP_STYLE_URL;
  const host = useRef<HTMLDivElement | null>(null);
  const [map, setMap] = useState<MapLibreMap | null>(null);
  const [failed, setFailed] = useState(false);
  // the newest props, read by the map's event handlers (set after every render, never during one)
  const handlers = useRef({ onViewport, onSelectHazard, onMapPress });
  useEffect(() => {
    handlers.current = { onViewport, onSelectHazard, onMapPress };
  });

  // create the map once; a changed style swaps it with setStyle below
  useEffect(() => {
    let cancelled = false;
    let created: MapLibreMap | null = null;
    loadMapLibre()
      .then((lib) => {
        if (cancelled || !host.current) return;
        created = new lib.Map({
          container: host.current,
          style: styleUrl ?? plainStyle(background),
          center: START.center,
          zoom: START.zoom,
          attributionControl: false,
          dragRotate: false,
          pitchWithRotate: false,
        });
        created.touchZoomRotate.disableRotation();
        created.on('load', () => {
          if (!created) return;
          addLayers(created);
          setMap(created);
          (window as unknown as { __tnMap?: MapLibreMap }).__tnMap = created; // read by the browser tests
          reportViewport(created);
        });
        created.on('moveend', () => created && reportViewport(created));
        created.on('click', 'hazards-circle', (event) => {
          const id = event.features?.[0]?.properties?.id;
          if (typeof id === 'string') {
            (event.originalEvent as { tnHandled?: boolean }).tnHandled = true;
            handlers.current.onSelectHazard(id);
          }
        });
        created.on('click', (event) => {
          if ((event.originalEvent as { tnHandled?: boolean }).tnHandled) return;
          handlers.current.onMapPress({ lat: event.lngLat.lat, lng: event.lngLat.lng });
        });
        created.on('mouseenter', 'hazards-circle', () => created && (created.getCanvas().style.cursor = 'pointer'));
        created.on('mouseleave', 'hazards-circle', () => created && (created.getCanvas().style.cursor = ''));
      })
      .catch(() => setFailed(true));
    function reportViewport(m: MapLibreMap) {
      const center = m.getCenter();
      const corner = m.getBounds().getNorthEast();
      handlers.current.onViewport({ lat: center.lat, lng: center.lng, radiusMeters: radiusFor({ lat: center.lat, lng: center.lng }, { lat: corner.lat, lng: corner.lng }) });
    }
    return () => {
      cancelled = true;
      created?.remove();
      setMap(null);
      delete (window as unknown as { __tnMap?: MapLibreMap }).__tnMap;
    };
    // the style is chosen at creation; a change of the colour scheme or the style URL rebuilds the map
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [styleUrl, styleUrl ? '' : background]);

  // The device's position is often known before the map is: go there once, the first time both are there.
  const centered = useRef(false);
  useEffect(() => {
    if (!map || centered.current || !userPosition) return;
    centered.current = true;
    map.jumpTo({ center: [userPosition.lng, userPosition.lat], zoom: 12 });
  }, [map, userPosition]);

  // the camera the screen drives (`flyTo`), same shape as the native one
  useEffect(() => {
    if (!map) return;
    cameraRef.current = {
      flyTo: (options: { center: [number, number]; zoom?: number; duration?: number }) => map.flyTo({ center: options.center, zoom: options.zoom, duration: options.duration }),
    } as unknown as CameraRef;
    return () => {
      cameraRef.current = null;
    };
  }, [map, cameraRef]);

  useEffect(() => {
    if (!map) return;
    (map.getSource('hazards') as GeoJSONSourceLike | undefined)?.setData(data.hazards);
    (map.getSource('signs') as GeoJSONSourceLike | undefined)?.setData(data.signs);
    (map.getSource('zones') as GeoJSONSourceLike | undefined)?.setData(data.zones);
  }, [map, data]);

  useEffect(() => {
    if (!map) return;
    const feature = draft ? [{ type: 'Feature', properties: {}, geometry: { type: 'Point', coordinates: [draft.lng, draft.lat] } }] : [];
    (map.getSource('draft') as GeoJSONSourceLike | undefined)?.setData({ type: 'FeatureCollection', features: feature } as never);
  }, [map, draft]);

  useEffect(() => {
    if (!map) return;
    const features = showUserLocation && userPosition ? [{ type: 'Feature', properties: {}, geometry: { type: 'Point', coordinates: [userPosition.lng, userPosition.lat] } }] : [];
    (map.getSource('me') as GeoJSONSourceLike | undefined)?.setData({ type: 'FeatureCollection', features } as never);
  }, [map, showUserLocation, userPosition]);

  return (
    <View style={[styles.box, { backgroundColor: background }]}>
      {createElement('div', { ref: host, style: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }, role: 'application', 'aria-label': t('tabs.map') })}
      {failed ? <View style={styles.box} /> : null}
    </View>
  );
}

type GeoJSONSourceLike = { setData(data: unknown): void };

function addLayers(map: MapLibreMap) {
  for (const id of ['zones', 'signs', 'draft', 'hazards', 'me']) map.addSource(id, { type: 'geojson', data: EMPTY as never, promoteId: id === 'hazards' ? 'id' : undefined });
  map.addLayer({ id: 'zones-fill', type: 'fill', source: 'zones', paint: { 'fill-color': '#862E9C', 'fill-opacity': 0.22 } });
  map.addLayer({ id: 'zones-line', type: 'line', source: 'zones', paint: { 'line-color': '#862E9C', 'line-width': 2, 'line-dasharray': [2, 2] } });
  map.addLayer({ id: 'signs-circle', type: 'circle', source: 'signs', paint: { 'circle-radius': 4, 'circle-color': '#495057', 'circle-stroke-width': 1, 'circle-stroke-color': '#FFFFFF' } });
  map.addLayer({ id: 'draft-ring', type: 'circle', source: 'draft', paint: { 'circle-radius': 14, 'circle-color': '#FFFFFF', 'circle-opacity': 0, 'circle-stroke-width': 4, 'circle-stroke-color': '#C92A2A' } });
  map.addLayer({ id: 'me-dot', type: 'circle', source: 'me', paint: { 'circle-radius': 8, 'circle-color': '#0A84FF', 'circle-stroke-width': 3, 'circle-stroke-color': '#FFFFFF' } });
  map.addLayer({ id: 'hazards-circle', type: 'circle', source: 'hazards', paint: { 'circle-radius': 10, 'circle-color': hazardColorExpression() as never, 'circle-stroke-width': 2.5, 'circle-stroke-color': '#FFFFFF' } });
}

const styles = StyleSheet.create({ box: { flex: 1 } });
