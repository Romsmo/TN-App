import { Camera, GeoJSONSource, Layer, Map, UserLocation, type CameraRef, type StyleSpecification } from '@maplibre/maplibre-react-native';
import { StyleSheet } from 'react-native';

import { MAP_STYLE_URL } from '@/config';
import { hazardColorExpression } from '@/map/colors';
import type { MapData } from '@/map/geojson';
import { radiusFor, type Viewport } from './use-nearby';

/** Start view when the position is unknown: Europe. */
const START = { center: [10, 50] as [number, number], zoom: 4 };

/** Plain background: used while no map source is set up (see config.ts). Only the Trafficnetwork's own layers show. */
function plainStyle(background: string): StyleSpecification {
  return { version: 8, sources: {}, layers: [{ id: 'background', type: 'background', paint: { 'background-color': background } }] };
}

type Props = {
  data: MapData;
  background: string;
  showUserLocation: boolean;
  onViewport: (viewport: Viewport) => void;
  onSelectHazard: (id: string) => void;
  /** A tap on empty map (not on a report). */
  onMapPress: (position: { lat: number; lng: number }) => void;
  /** The spot the user marked for a new report. */
  draft: { lat: number; lng: number } | null;
  cameraRef: React.RefObject<CameraRef | null>;
};

/**
 * The MapLibre map. Native code: this file is not covered by the unit tests, the data it draws is (map/geojson.ts).
 * Zones are drawn as areas only; there is deliberately no point layer for them.
 */
export function MapView({ data, background, showUserLocation, onViewport, onSelectHazard, onMapPress, draft, cameraRef }: Props) {
  return (
    <Map
      style={styles.map}
      mapStyle={MAP_STYLE_URL ?? plainStyle(background)}
      attribution={false}
      logo={false}
      onPress={(event) => {
        const [lng, lat] = event.nativeEvent.lngLat;
        onMapPress({ lat, lng });
      }}
      onRegionDidChange={(event) => {
        const { center, bounds } = event.nativeEvent;
        const [lng, lat] = center;
        const [, , east, north] = bounds;
        onViewport({ lat, lng, radiusMeters: radiusFor({ lat, lng }, { lat: north, lng: east }) });
      }}>
      <Camera ref={cameraRef} initialViewState={START} />
      {showUserLocation ? <UserLocation /> : null}
      <GeoJSONSource id="zones" data={data.zones}>
        <Layer id="zones-fill" type="fill" paint={{ 'fill-color': '#862E9C', 'fill-opacity': 0.22 }} />
        <Layer id="zones-line" type="line" paint={{ 'line-color': '#862E9C', 'line-width': 2, 'line-dasharray': [2, 2] }} />
      </GeoJSONSource>
      <GeoJSONSource id="signs" data={data.signs}>
        <Layer id="signs-circle" type="circle" paint={{ 'circle-radius': 4, 'circle-color': '#495057', 'circle-stroke-width': 1, 'circle-stroke-color': '#FFFFFF' }} />
      </GeoJSONSource>
      <GeoJSONSource
        id="draft"
        data={{
          type: 'FeatureCollection',
          features: draft ? [{ type: 'Feature', properties: {}, geometry: { type: 'Point', coordinates: [draft.lng, draft.lat] } }] : [],
        }}>
        <Layer id="draft-ring" type="circle" paint={{ 'circle-radius': 14, 'circle-color': '#FFFFFF', 'circle-opacity': 0.0, 'circle-stroke-width': 4, 'circle-stroke-color': '#C92A2A' }} />
      </GeoJSONSource>
      <GeoJSONSource
        id="hazards"
        data={data.hazards}
        onPress={(event) => {
          const id = event.nativeEvent.features?.[0]?.properties?.id;
          if (typeof id === 'string') onSelectHazard(id);
        }}>
        <Layer
          id="hazards-circle"
          type="circle"
          paint={{ 'circle-radius': 10, 'circle-color': hazardColorExpression(), 'circle-stroke-width': 2.5, 'circle-stroke-color': '#FFFFFF' }}
        />
      </GeoJSONSource>
    </Map>
  );
}

const styles = StyleSheet.create({ map: { flex: 1 } });
