import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:tn_core/tn_core.dart' hide LatLng;
import 'package:tn_core/tn_core.dart' as core show LatLng;

import '../../platform/platform.dart' show demoMode;
import '../../services/app_config.dart';

/// What the map screen needs to move the camera.
class MapHandle {
  MapLibreMapController? _controller;
  bool _programmatic = false;

  bool get ready => _controller != null;

  Future<void> flyTo(double lat, double lng, {double? zoom, int ms = 600}) async {
    final c = _controller;
    if (c == null) return;
    _programmatic = true;
    try {
      await c.animateCamera(
        zoom != null ? CameraUpdate.newLatLngZoom(LatLng(lat, lng), zoom) : CameraUpdate.newLatLng(LatLng(lat, lng)),
        duration: Duration(milliseconds: ms),
      );
    } catch (_) {}
    // the idle callback of the animation clears the flag; make sure it is cleared even without one
    Timer(Duration(milliseconds: ms + 400), () => _programmatic = false);
  }
}

/// The position shown on the map: an arrow turning with the heading, and a circle for the accuracy (in metres).
class UserMark {
  const UserMark({required this.lat, required this.lng, this.heading, this.accuracyM});
  final double lat;
  final double lng;
  final double? heading;
  final double? accuracyM;
}

/// The default background map, the same source as the operator's web map: OpenStreetMap's raster tiles. Their usage policy
/// (operations.osmfoundation.org/policies/tiles, read 2026-10-24) allows apps that send an identifying User-Agent (see
/// [_identifyToTileServer]), show the credit and honour the cache headers; offline downloads and prefetching are not allowed.
/// In dark mode the tiles are dimmed (no dark OSM tiles exist).
String _osmStyle(String background, bool dark) => jsonEncode({
      'version': 8,
      'sources': {
        'osm': {
          'type': 'raster',
          'tiles': ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
          'tileSize': 256,
          'maxzoom': 19,
          'attribution': mapAttribution,
        },
      },
      'layers': [
        {
          'id': 'background',
          'type': 'background',
          'paint': {'background-color': background},
        },
        {
          'id': 'osm',
          'type': 'raster',
          'source': 'osm',
          'paint': dark
              ? {'raster-brightness-max': 0.45, 'raster-saturation': -0.4, 'raster-contrast': 0.1}
              : <String, Object>{},
        },
      ],
    });

String _styleFor(Color background, bool dark) {
  final url = dark && (buildConfig.mapStyleUrlDark?.isNotEmpty ?? false) ? buildConfig.mapStyleUrlDark : buildConfig.mapStyleUrl;
  if (url != null && url.isNotEmpty) return url;
  final hex = '#${(background.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  return _osmStyle(hex, dark);
}

bool _identified = false;

/// OpenStreetMap blocks the generic User-Agent of a map library, so the app names itself once (no personal data).
Future<void> _identifyToTileServer() async {
  if (_identified || demoMode) return;
  _identified = true;
  try {
    await setHttpHeaders({'User-Agent': 'TNViewer/$appVersion (+$sourceRepoUrl)'});
  } catch (_) {
    // The map still works; OpenStreetMap may then refuse the tiles.
  }
}

/// The arrow of the position: polygon (32,5) (54,56) (32,44) (10,56) on a 64x64 canvas, blue with a white border.
Future<Uint8List> _arrowPng() async {
  const size = 64.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final path = Path()
    ..moveTo(32, 5)
    ..lineTo(54, 56)
    ..lineTo(32, 44)
    ..lineTo(10, 56)
    ..close();
  canvas.drawPath(
    path,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeJoin = StrokeJoin.round,
  );
  canvas.drawPath(path, Paint()..color = const Color(0xFF0A84FF));
  final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// A circle of [radiusM] metres around a point as a GeoJSON polygon.
Map<String, Object?> _circle(double lat, double lng, double radiusM) {
  const steps = 48;
  final ring = <List<double>>[];
  for (var i = 0; i <= steps; i++) {
    final p = destination(core.LatLng(lat, lng), 360.0 * i / steps, radiusM);
    ring.add([p.lng, p.lat]);
  }
  return {
    'type': 'Feature',
    'geometry': {
      'type': 'Polygon',
      'coordinates': [ring],
    },
    'properties': <String, Object?>{},
  };
}

Map<String, Object?> _fc(List<Map<String, Object?>> features) => {'type': 'FeatureCollection', 'features': features};

Map<String, Object?> _pointFeature(double lat, double lng, [Map<String, Object?> props = const {}]) => {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [lng, lat],
      },
      'properties': props,
    };

/// The MapLibre map with the Trafficnetwork's layers: camera zones as areas (never as points), signs, reports, the position
/// and the marked spot. Without a style URL the map is a plain surface and shows only these layers.
class TnMapView extends StatefulWidget {
  const TnMapView({
    super.key,
    required this.data,
    required this.background,
    required this.dark,
    required this.handle,
    this.user,
    required this.onViewport,
    required this.onSelectHazard,
    required this.onMapPress,
    required this.onUserMove,
    this.draft,
    this.draftEnd,
    this.interval,
  });

  final MapData data;
  final Color background;
  final bool dark;
  final MapHandle handle;
  final UserMark? user;

  /// Called when the visible area changed: centre and a radius that covers it.
  final void Function(double lat, double lng, double radiusM) onViewport;
  final void Function(String id) onSelectHazard;
  final void Function(double lat, double lng) onMapPress;
  final VoidCallback onUserMove;

  /// A marked spot (report location, speed-limit spot) and a second end for a stretch of road.
  final ({double lat, double lng})? draft;
  final ({double lat, double lng})? draftEnd;
  final List<({double lat, double lng})>? interval;

  @override
  State<TnMapView> createState() => _TnMapViewState();
}

class _TnMapViewState extends State<TnMapView> {
  MapLibreMapController? _c;
  bool _styleReady = false;
  late String _style;

  @override
  void initState() {
    super.initState();
    _identifyToTileServer();
    _style = _styleFor(widget.background, widget.dark);
  }

  @override
  void didUpdateWidget(TnMapView old) {
    super.didUpdateWidget(old);
    if (_styleReady) {
      if (!identical(old.data, widget.data)) _pushData();
      if (old.user != widget.user) _pushUser();
      if (old.draft != widget.draft || old.draftEnd != widget.draftEnd || old.interval != widget.interval) _pushDraft();
    }
  }

  Future<void> _onStyleLoaded() async {
    final c = _c;
    if (c == null) return;
    try {
      await c.addImage('arrow', await _arrowPng());
    } catch (_) {}
    Future<void> src(String id) => c.addGeoJsonSource(id, _fc(const []));
    for (final id in ['zones', 'signs', 'user-accuracy', 'draft', 'interval', 'hazards', 'user']) {
      await src(id);
    }
    await c.addFillLayer('zones', 'zones-fill', const FillLayerProperties(fillColor: '#862E9C', fillOpacity: 0.22), enableInteraction: false);
    await c.addLineLayer('zones', 'zones-line', const LineLayerProperties(lineColor: '#862E9C', lineWidth: 2, lineDasharray: [2, 2]), enableInteraction: false);
    await c.addLineLayer('interval', 'interval-line', const LineLayerProperties(lineColor: '#0A84FF', lineWidth: 5, lineOpacity: 0.8), enableInteraction: false);
    await c.addCircleLayer('signs', 'signs-dot', const CircleLayerProperties(circleColor: '#868E96', circleRadius: 4), enableInteraction: false);
    await c.addCircleLayer(
      'draft',
      'draft-ring',
      const CircleLayerProperties(circleColor: '#FF3B30', circleOpacity: 0.12, circleRadius: 14, circleStrokeColor: '#FF3B30', circleStrokeWidth: 3),
      enableInteraction: false,
    );
    final colorExpr = <Object>['match', ['get', 'type'], for (final e in hazardColors.entries) ...[e.key, e.value], unknownHazardColor];
    await c.addCircleLayer(
      'hazards',
      'hazards-dot',
      CircleLayerProperties(
        circleColor: colorExpr,
        circleRadius: 10,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
        circleOpacity: ['case', ['get', 'pending'], 0.6, 1.0],
      ),
      enableInteraction: false, // taps are resolved in _onTap, so the map also gets the taps that miss a marker
    );
    await c.addFillLayer('user-accuracy', 'user-accuracy-fill', const FillLayerProperties(fillColor: '#0A84FF', fillOpacity: 0.15), enableInteraction: false);
    await c.addSymbolLayer(
      'user',
      'user-arrow',
      const SymbolLayerProperties(
        iconImage: ['case', ['has', 'heading'], 'arrow', ''],
        iconSize: 0.6,
        iconRotate: ['get', 'heading'],
        iconRotationAlignment: 'map',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      enableInteraction: false,
    );
    await c.addCircleLayer(
      'user',
      'user-dot',
      const CircleLayerProperties(
        circleColor: '#0A84FF',
        circleRadius: 7,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
        circleOpacity: ['case', ['has', 'heading'], 0.0, 1.0],
        circleStrokeOpacity: ['case', ['has', 'heading'], 0.0, 1.0],
      ),
      enableInteraction: false,
    );
    _styleReady = true;
    await _pushData();
    await _pushUser();
    await _pushDraft();
    unawaited(_reportViewport());
  }

  Future<void> _pushData() async {
    final c = _c;
    if (c == null) return;
    try {
      await c.setGeoJsonSource('zones', widget.data.zones);
      await c.setGeoJsonSource('signs', widget.data.signs);
      await c.setGeoJsonSource('hazards', widget.data.hazards);
    } catch (_) {}
  }

  Future<void> _pushUser() async {
    final c = _c;
    if (c == null) return;
    final u = widget.user;
    try {
      await c.setGeoJsonSource(
        'user',
        _fc([if (u != null) _pointFeature(u.lat, u.lng, {if (u.heading != null) 'heading': u.heading})]),
      );
      await c.setGeoJsonSource(
        'user-accuracy',
        _fc([if (u != null && (u.accuracyM ?? 0) > 0) _circle(u.lat, u.lng, u.accuracyM!)]),
      );
    } catch (_) {}
  }

  Future<void> _pushDraft() async {
    final c = _c;
    if (c == null) return;
    try {
      await c.setGeoJsonSource(
        'draft',
        _fc([
          if (widget.draft != null) _pointFeature(widget.draft!.lat, widget.draft!.lng),
          if (widget.draftEnd != null) _pointFeature(widget.draftEnd!.lat, widget.draftEnd!.lng),
        ]),
      );
      final iv = widget.interval;
      await c.setGeoJsonSource(
        'interval',
        _fc([
          if (iv != null && iv.length >= 2)
            {
              'type': 'Feature',
              'geometry': {
                'type': 'LineString',
                'coordinates': [for (final p in iv) [p.lng, p.lat]],
              },
              'properties': <String, Object?>{},
            },
        ]),
      );
    } catch (_) {}
  }

  Future<void> _reportViewport() async {
    final c = _c;
    if (c == null || !_styleReady) return;
    try {
      final b = await c.getVisibleRegion();
      final center = core.LatLng((b.southwest.latitude + b.northeast.latitude) / 2, (b.southwest.longitude + b.northeast.longitude) / 2);
      final corner = core.LatLng(b.northeast.latitude, b.northeast.longitude);
      final meters = distanceMeters(center, corner);
      widget.onViewport(center.lat, center.lng, math.min(50000, math.max(500, meters.round())).toDouble());
    } catch (_) {}
  }

  Future<void> _onTap(math.Point<double> point, LatLng coordinates) async {
    final c = _c;
    if (c == null) return;
    try {
      final features = await c.queryRenderedFeaturesInRect(
        Rect.fromCenter(center: Offset(point.x, point.y), width: 40, height: 40),
        ['hazards-dot'],
        null,
      );
      if (features.isNotEmpty) {
        final f = features.first;
        final props = f is Map ? f['properties'] : null;
        final id = props is Map ? props['id'] : (f is Map ? f['id'] : null);
        if (id is String) {
          widget.onSelectHazard(id);
          return;
        }
      }
    } catch (_) {}
    widget.onMapPress(coordinates.latitude, coordinates.longitude);
  }

  @override
  Widget build(BuildContext context) {
    return MapLibreMap(
      key: ValueKey(_style),
      styleString: _style,
      // Europe; the demo data (development preview only) is around Munich
      initialCameraPosition: demoMode ? const CameraPosition(target: LatLng(48.21, 11.62), zoom: 10.5) : const CameraPosition(target: LatLng(50, 10), zoom: 4),
      trackCameraPosition: true,
      compassEnabled: true,
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: false,
      logoEnabled: false,
      attributionButtonPosition: AttributionButtonPosition.bottomLeft,
      onMapCreated: (c) {
        _c = c;
        widget.handle._controller = c;
      },
      onStyleLoadedCallback: _onStyleLoaded,
      onMapClick: _onTap,
      onCameraMove: (_) {
        if (!widget.handle._programmatic) widget.onUserMove();
      },
      onCameraIdle: () {
        widget.handle._programmatic = false;
        unawaited(_reportViewport());
      },
    );
  }
}

/// Used by tests to read a feature collection back.
String debugJson(Map<String, Object?> m) => jsonEncode(m);
