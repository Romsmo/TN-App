import { createContext, useContext, useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { hazardColor } from '@/map/colors';

/** A drawing of a map for the UI preview: the real map is native and cannot run in a browser. Same props, flat picture. */
const CENTER = { lng: 11.6, lat: 48.2 };
const DEG_PER_PX_LAT = 0.00009;
const DEG_PER_PX_LNG = DEG_PER_PX_LAT / Math.cos((CENTER.lat * Math.PI) / 180);

type Size = { w: number; h: number };
const MapContext = createContext<{ size: Size; project: (lng: number, lat: number) => { x: number; y: number } } | null>(null);

type Feature = { geometry: { type: string; coordinates: any }; properties?: Record<string, any> | null };

export function Map({ children, onPress, onRegionDidChange, style, mapStyle }: any) {
  const [size, setSize] = useState<Size>({ w: 390, h: 560 });
  const project = (lng: number, lat: number) => ({ x: size.w / 2 + (lng - CENTER.lng) / DEG_PER_PX_LNG, y: size.h / 2 - (lat - CENTER.lat) / DEG_PER_PX_LAT });
  const unproject = (x: number, y: number): [number, number] => [CENTER.lng + (x - size.w / 2) * DEG_PER_PX_LNG, CENTER.lat - (y - size.h / 2) * DEG_PER_PX_LAT];

  useEffect(() => {
    const [west, north] = unproject(0, 0);
    const [east, south] = unproject(size.w, size.h);
    onRegionDidChange?.({ nativeEvent: { center: [CENTER.lng, CENTER.lat], zoom: 12, bearing: 0, pitch: 0, bounds: [west, south, east, north], animated: false, userInteraction: false } });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [size.w, size.h]);

  const background = mapStyle?.layers?.[0]?.paint?.['background-color'] ?? '#E9EDF1';
  return (
    <MapContext.Provider value={{ size, project }}>
      <View style={[style, { backgroundColor: background, overflow: 'hidden' }]} onLayout={(e) => setSize({ w: e.nativeEvent.layout.width, h: e.nativeEvent.layout.height })}>
        <Pressable
          accessibilityLabel="map"
          style={StyleSheet.absoluteFill}
          onPress={(e: any) => onPress?.({ nativeEvent: { lngLat: unproject(e.nativeEvent.locationX ?? size.w / 2, e.nativeEvent.locationY ?? size.h / 2), point: { x: 0, y: 0 } } })}>
          {/* a few "roads" so the drawing reads as a map */}
          {[0.25, 0.5, 0.78].map((f, i) => (
            <View key={i} style={{ position: 'absolute', left: -40, right: -40, top: size.h * f, height: i === 1 ? 10 : 6, backgroundColor: 'rgba(120,130,145,0.28)', transform: [{ rotate: `${-14 + i * 17}deg` }] }} />
          ))}
          {[0.2, 0.62].map((f, i) => (
            <View key={i} style={{ position: 'absolute', top: -40, bottom: -40, left: size.w * f, width: 6, backgroundColor: 'rgba(120,130,145,0.22)', transform: [{ rotate: `${12 - i * 25}deg` }] }} />
          ))}
        </Pressable>
        <Text style={styles.label}>Kartenvorschau (Attrappe)</Text>
        {children}
      </View>
    </MapContext.Provider>
  );
}

export function Camera(): null {
  return null;
}
export function UserLocation() {
  const ctx = useContext(MapContext);
  if (!ctx) return null;
  const { x, y } = ctx.project(CENTER.lng, CENTER.lat);
  return <View pointerEvents="none" style={{ position: 'absolute', left: x - 9, top: y - 9, width: 18, height: 18, borderRadius: 9, backgroundColor: '#1C7ED6', borderWidth: 3, borderColor: '#fff' }} />;
}
export function Layer(): null {
  return null;
}

export function GeoJSONSource({ id, data, onPress }: any) {
  const ctx = useContext(MapContext);
  if (!ctx) return null;
  const features: Feature[] = data?.features ?? [];
  return (
    <>
      {features.map((f, i) => {
        if (f.geometry.type === 'Point') {
          const [lng, lat] = f.geometry.coordinates as [number, number];
          const { x, y } = ctx.project(lng, lat);
          if (id === 'draft') return <View key={i} pointerEvents="none" style={{ position: 'absolute', left: x - 14, top: y - 14, width: 28, height: 28, borderRadius: 14, borderWidth: 4, borderColor: '#C92A2A' }} />;
          const size = id === 'signs' ? 8 : 22;
          return (
            <Pressable
              key={i}
              accessibilityRole="button"
              accessibilityLabel={`${f.properties?.type ?? 'item'}`}
              onPress={() => onPress?.({ nativeEvent: { features: [f], lngLat: [lng, lat], point: { x, y } } })}
              style={{ position: 'absolute', left: x - size / 2, top: y - size / 2, width: size, height: size, borderRadius: size / 2, backgroundColor: id === 'signs' ? '#495057' : hazardColor(String(f.properties?.type)), borderWidth: 2.5, borderColor: '#fff' }}
            />
          );
        }
        if (f.geometry.type === 'Polygon') {
          const ring = (f.geometry.coordinates[0] as [number, number][]).map(([lng, lat]) => ctx.project(lng, lat));
          const xs = ring.map((p) => p.x);
          const ys = ring.map((p) => p.y);
          return <View key={i} pointerEvents="none" style={{ position: 'absolute', left: Math.min(...xs), top: Math.min(...ys), width: Math.max(...xs) - Math.min(...xs), height: Math.max(...ys) - Math.min(...ys), backgroundColor: 'rgba(134,46,156,0.22)', borderWidth: 2, borderStyle: 'dashed', borderColor: '#862E9C' }} />;
        }
        return null;
      })}
    </>
  );
}

const styles = StyleSheet.create({ label: { position: 'absolute', alignSelf: 'center', bottom: 86, fontSize: 11, color: '#8A94A0', backgroundColor: 'rgba(128,128,128,0.18)', paddingHorizontal: 6, borderRadius: 4 } });
