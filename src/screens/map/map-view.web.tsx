import { StyleSheet, Text, View } from 'react-native';

import { useTheme } from '@/theme';

import type { MapViewProps } from './map-view';

/** Placeholder until the browser map (maplibre-gl) is in: the screens around it work, the list shows the reports. */
export function MapView({ background }: MapViewProps) {
  const theme = useTheme();
  return (
    <View style={[styles.box, { backgroundColor: background }]}>
      <Text style={{ color: theme.textSecondary }}>Karte folgt</Text>
    </View>
  );
}

const styles = StyleSheet.create({ box: { flex: 1, alignItems: 'center', justifyContent: 'center' } });
