import 'dart:async';
import 'dart:math' as math;

import 'package:tn_core/tn_core.dart';

/// A stand-in for the client library with invented data around Munich, for development only: the browser preview and
/// `--dart-define=TN_DEMO=true` builds. It is never part of a release build and makes no network connection.
class DemoBackend implements TnBackend {
  DemoBackend() {
    _hazards.addAll([
      _demoHazard('demo-1', 'accident', 48.2086, 11.6130, confirm: 3),
      _demoHazard('demo-2', 'traffic', 48.2142, 11.6470, confirm: 5),
      _demoHazard('demo-3', 'construction', 48.1950, 11.5900, confirm: 2),
      _demoHazard('demo-4', 'ice', 48.2240, 11.6700, confirm: 1),
      _demoHazard('demo-5', 'breakdown', 48.1800, 11.6200, confirm: 0),
    ]);
  }

  final List<Map<String, Object?>> _hazards = [];
  final _events = StreamController<Map<String, Object?>>.broadcast();
  int _pending = 0;
  int _localId = 0;
  Map<String, Object?> _offline = {'mode': 'auto', 'regions': <String>[], 'home': null, 'maxBytes': null, 'wifiOnly': true};

  static Map<String, Object?> _demoHazard(String id, String type, double lat, double lng, {int confirm = 0}) => {
        'kind': 'hazard',
        'id': id,
        'hazardType': type,
        'lat': lat,
        'lng': lng,
        'distanceMeters': 0,
        'expiresAt': DateTime.now().toUtc().add(const Duration(hours: 2, minutes: 20)).toIso8601String(),
        'confirmCount': confirm,
        'denyCount': 0,
        'pending': false,
      };

  static double _dist(double lat1, double lng1, double lat2, double lng2) {
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.pow(math.sin(dLat / 2), 2) + math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * math.pow(math.sin(dLng / 2), 2);
    return 2 * 6371000 * math.asin(math.min(1, math.sqrt(a)));
  }

  @override
  Future<Object?> call(String method, Map<String, Object?> args) async {
    switch (method) {
      case 'version':
        return {'apiVersion': 1, 'libraryVersion': 'demo'};
      case 'getNearby':
        final lat = (args['lat'] as num).toDouble();
        final lng = (args['lng'] as num).toDouble();
        final r = (args['radiusMeters'] as num).toDouble();
        final items = <Map<String, Object?>>[
          for (final h in _hazards)
            if (_dist(lat, lng, h['lat'] as double, h['lng'] as double) <= r)
              {...h, 'distanceMeters': _dist(lat, lng, h['lat'] as double, h['lng'] as double)},
          {'kind': 'sign', 'id': 'sign-1', 'signType': 'speedLimit50', 'lat': 48.2005, 'lng': 11.602, 'distanceMeters': 0},
          {'kind': 'sign', 'id': 'sign-2', 'signType': 'speedLimit100', 'lat': 48.2102, 'lng': 11.628, 'distanceMeters': 0},
          {
            'kind': 'cameraZone',
            'id': 'zone-1',
            'cell': 'demo',
            'resolution': 7,
            'cameraTypes': ['mobileSpeedCamera'],
            'distanceMeters': 0,
            'outline': [
              [11.633, 48.2175],
              [11.645, 48.2175],
              [11.645, 48.2230],
              [11.633, 48.2230],
            ],
          },
        ];
        return {'items': items};
      case 'getSpeedLimitAt':
        return {
          'value': 50,
          'unit': 'kmh',
          'segmentId': 'demo',
          'distanceMeters': 3,
          'origin': {'kind': 'imported'},
        };
      case 'lookupSpeedLimit':
        final lat = (args['lat'] as num).toDouble();
        final lng = (args['lng'] as num).toDouble();
        if (lat > 48.25) return {'status': 'outsideOfflineArea'};
        if ((lng * 1000).floor() % 2 == 0) {
          return {'status': 'found', 'source': 'offline', 'value': 70, 'unit': 'kmh', 'segmentId': 's', 'distanceMeters': 2, 'origin': {'kind': 'imported'}};
        }
        return {'status': 'notRecorded', 'source': 'offline'};
      case 'getCoverage':
        final lat = (args['lat'] as num).toDouble();
        return {'covered': lat < 48.25, 'tile': 'demo', 'state': 'stored', 'usesNetwork': false};
      case 'updatePosition':
        return {'tiles': <String>['demo'], 'changed': false};
      case 'planBootstrap':
        return {'partitionsTotal': 4, 'partitionsPending': 0, 'bytesTotal': 123456789, 'bytesPending': 0};
      case 'tick':
        return {'synced': true, 'report': _report()};
      case 'sync':
        final r = _report();
        _pending = 0;
        return r;
      case 'getSyncStatus':
        return {
          'connection': 'online',
          'lastSyncedAtUnixMs': DateTime.now().millisecondsSinceEpoch,
          'pendingWrites': _pending,
          'subscribedTiles': ['demo'],
          'staticDataVersion': 1,
          'storageBytes': 48000000,
        };
      case 'getNetworkStatus':
        return {
          'knownNodes': [
            {'nodeId': 'demo-1', 'address': 'https://demo.invalid', 'tier': 'active', 'backedOff': false},
          ],
          'activeNodes': ['demo-1'],
          'currentNodes': ['demo-1'],
          'configVersion': 1,
          'cameraNamespaceEnabled': false,
          'onlineNetwork': 42,
          'onlineEstimated': false,
        };
      case 'getCameraPolicy':
        return {
          'hostEnabled': true,
          'active': args.isEmpty || true,
          'enabled': true,
          'maxLevel': 'zones',
          'defaultLevel': 'zones',
          'zoneResolution': 7,
          'version': '1',
          'notice': {'version': '1', 'text': {'de': '', 'en': ''}},
        };
      case 'getReportLimits':
        return {'supported': true, 'defaultSeconds': 7200, 'minSeconds': 600, 'maxSeconds': 1209600};
      case 'submitReport':
        _pending++;
        final id = 'local-${++_localId}';
        _hazards.add({
          ..._demoHazard(id, args['type'] as String, (args['lat'] as num).toDouble(), (args['lng'] as num).toDouble()),
          'expiresAt': null,
          'pending': true,
        });
        _events.add({'type': 'dataChanged', 'entityType': 'hazard', 'entityId': id, 'eventType': 'created'});
        return {'localId': id, 'durationHonoured': args['ttlSeconds'] != null ? true : null};
      case 'confirmReport':
      case 'reportCameraRemoved':
        _pending++;
        return {'localId': 'local-${++_localId}'};
      case 'reportWrongSpeedLimit':
      case 'reportSpeedLimitInterval':
        _pending++;
        return {'value': args['proposedValue'] ?? args['value'], 'unit': args['unit'], 'confirmations': 0};
      case 'resolveRoadInterval':
        return {'road': 'Demostraße', 'lengthM': 420};
      case 'getOfflineSettings':
        return _offline;
      case 'setOfflineRegions':
        _offline = {
          ..._offline,
          if (args['mode'] != null) 'mode': args['mode'],
          if (args['regions'] != null) ...{'regions': args['regions'], if (args['mode'] == null) 'mode': 'regions'},
        };
        return _offline;
      case 'setStorageLimits':
        _offline = {..._offline, if (args.containsKey('maxBytes')) 'maxBytes': args['maxBytes'], if (args.containsKey('wifiOnly')) 'wifiOnly': args['wifiOnly']};
        return _offline;
      case 'listOfflineRegions':
        final sel = (_offline['regions'] as List).cast<String>();
        return {
          'regions': [
            for (final e in [('de', 'DE', 410000000), ('at', 'AT', 90000000), ('ch', 'CH', 70000000)])
              {
                'id': e.$1,
                'country': e.$2,
                'tileCount': 200,
                'downloadBytes': e.$3 ~/ 3,
                'sizeBytes': e.$3,
                'estimatedDeviceBytes': e.$3,
                'complete': e.$1 != 'ch',
                'selected': sel.contains(e.$1),
                'storedTiles': e.$1 == 'de' ? 200 : 0,
                'state': e.$1 == 'de' ? 'complete' : 'none',
              },
          ],
        };
      case 'getStoragePlan':
        return {'mode': _offline['mode'], 'needsLocation': false, 'toFetchTiles': 0, 'toFetchBytes': 0, 'toRemoveTiles': 0, 'deferredTiles': 0, 'maxBytes': _offline['maxBytes'], 'fits': true, 'storedTiles': 200, 'storedDeviceBytes': 410000000};
      case 'getStorageUsage':
        return {'storedTiles': 200, 'storeBytes': 410000000, 'storedJsonBytes': 12000000, 'estimatedDeviceBytes': 410000000, 'maxBytes': _offline['maxBytes']};
      default:
        throw TnError('internal', 'demo backend: $method is not simulated');
    }
  }

  Map<String, Object?> _report() => {'skipped': false, 'ok': true, 'submitted': _pending, 'rejected': 0, 'pendingWrites': 0, 'needsLocation': false};

  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  @override
  Future<void> startRealtime() async {}

  @override
  Future<void> stopRealtime() async {}

  @override
  Future<void> close() async {
    await _events.close();
  }
}
