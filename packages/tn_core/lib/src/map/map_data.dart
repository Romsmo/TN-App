import '../tn/types.dart';
import 'camera_types.dart';

/// GeoJSON layers for the map, as plain JSON-ready maps.
class MapData {
  const MapData({required this.hazards, required this.signs, required this.zones});
  final Map<String, Object?> hazards;
  final Map<String, Object?> signs;

  /// Areas only. A camera zone never becomes a point (the country policy says "zones", not "locations").
  final Map<String, Object?> zones;
}

Map<String, Object?> _collection(List<Map<String, Object?>> features) => {'type': 'FeatureCollection', 'features': features};

Map<String, Object?> _point(String id, double lat, double lng, Map<String, Object?> properties) => {
      'type': 'Feature',
      'id': id,
      'geometry': {'type': 'Point', 'coordinates': [lng, lat]},
      'properties': properties,
    };

Map<String, Object?>? _zonePolygon(CameraZoneItem zone) {
  final ring = zone.outline;
  if (ring.length < 3) return null;
  final first = ring.first;
  final last = ring.last;
  final closed = first[0] == last[0] && first[1] == last[1] ? ring : [...ring, first];
  return {
    'type': 'Feature',
    'id': zone.id,
    'geometry': {
      'type': 'Polygon',
      'coordinates': [closed],
    },
    'properties': {'id': zone.id, 'cameraTypes': zone.cameraTypes.join(',')},
  };
}

/// Turns what the library returns into map layers. Individual cameras (`CameraItem`) are drawn as hazard-like points
/// only when the library delivered them, which it does only when the user switched cameras on and the country policy
/// allows it; this function adds no gate of its own and never invents one.
MapData toMapData(List<NearbyItem> items, {required Set<String> hiddenHazardTypes}) {
  final hazards = <Map<String, Object?>>[];
  final signs = <Map<String, Object?>>[];
  final zones = <Map<String, Object?>>[];

  for (final item in items) {
    switch (item) {
      case HazardItem():
        if (isTypeHidden(item.hazardType, hiddenHazardTypes)) break;
        hazards.add(_point(item.id, item.lat, item.lng, {
          'id': item.id,
          'kind': 'hazard',
          'type': item.hazardType,
          'confirmCount': item.confirmCount,
          'denyCount': item.denyCount,
          'pending': item.pending,
        }));
      case CameraItem():
        if (isTypeHidden(item.cameraType, hiddenHazardTypes)) break;
        hazards.add(_point(item.id, item.lat, item.lng, {
          'id': item.id,
          'kind': 'camera',
          'type': item.cameraType,
          'confirmCount': 0,
          'denyCount': 0,
          'pending': false,
        }));
      case SignItem():
        signs.add(_point(item.id, item.lat, item.lng, {'id': item.id, 'kind': 'sign', 'type': item.signType}));
      case CameraZoneItem():
        if (hiddenHazardTypes.contains(camerasGroup)) break;
        final polygon = _zonePolygon(item);
        if (polygon != null) zones.add(polygon);
    }
  }
  return MapData(hazards: _collection(hazards), signs: _collection(signs), zones: _collection(zones));
}

/// The distinct types present in the data, for the filter chips: the list comes from the data, not from the app.
/// All camera types (reports, fixed devices, zones) collapse into one entry, the camera group.
List<String> hazardTypesIn(List<NearbyItem> items) {
  final types = <String>{};
  for (final item in items) {
    if (item is HazardItem) {
      types.add(isCameraType(item.hazardType) ? camerasGroup : item.hazardType);
    } else if (item is CameraItem || item is CameraZoneItem) {
      types.add(camerasGroup);
    }
  }
  return types.toList()..sort();
}

/// What a pin on the map is: a report (with votes) or a permanently installed device.
String pointType(NearbyItem item) => switch (item) {
      HazardItem() => item.hazardType,
      CameraItem() => item.cameraType,
      _ => '',
    };
