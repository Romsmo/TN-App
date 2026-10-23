import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tn_core/tn_core.dart';
import 'package:tnviewer/app_scope.dart';
import 'package:tnviewer/screens/drive_screen.dart';
import 'package:tnviewer/screens/map/detail_card.dart';
import 'package:tnviewer/screens/map/report_sheet.dart';
import 'package:tnviewer/screens/map/speed_limit_card.dart';
import 'package:tnviewer/services/app_config.dart';
import 'package:tnviewer/services/drive_controller.dart';
import 'package:tnviewer/services/legal.dart';
import 'package:tnviewer/services/location.dart';
import 'package:tnviewer/services/stores.dart';
import 'package:tnviewer/services/tn_controller.dart';
import 'package:tnviewer/ui/theme.dart';

Map<String, String> _table(String lang) =>
    (jsonDecode(File('assets/texts/$lang.json').readAsStringSync()) as Map).cast<String, String>();

Future<AppServices> _services() async {
  final texts = Texts(de: _table('de'), en: _table('en'), language: 'de');
  final settings = await SettingsStore.open(buildConfig);
  final credentials = await CredentialsStore.open();
  final tn = TnController(settings: settings, credentials: credentials);
  final drive = DriveController(tn: tn, settings: settings, texts: texts);
  // LegalTexts.load needs the asset bundle; the widget tests read the same file directly
  final legal = await LegalTexts.load();
  return AppServices(texts: texts, legal: legal, settings: settings, credentials: credentials, tn: tn, drive: drive, position: DevicePosition());
}

Widget _host(AppServices s, Widget child) => AppScope(
      services: s,
      child: MaterialApp(
        theme: buildTheme(TnColors.light),
        home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.all(16), child: child))),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('de');
  });

  testWidgets('DetailCard shows a hazard with votes and the remaining time', (tester) async {
    final s = (await tester.runAsync(_services))!;
    final item = HazardItem(
      id: 'h1',
      hazardType: 'accident',
      lat: 1,
      lng: 2,
      distanceMeters: 450,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2, minutes: 5)).toIso8601String(),
      confirmCount: 3,
      denyCount: 1,
      pending: false,
    );
    await tester.pumpWidget(_host(s, DetailCard(item: item, onClose: () {}, onVote: (_) {})));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Unfall'), findsOneWidget);
    expect(find.textContaining('3 Bestätigungen'), findsOneWidget);
    expect(find.text('Ist noch da'), findsOneWidget);
  });

  testWidgets('DetailCard for a fixed camera offers "Gibt es nicht mehr"', (tester) async {
    final s = (await tester.runAsync(_services))!;
    const item = CameraItem(id: 'c1', cameraType: 'fixedSpeedCamera', lat: 1, lng: 2, distanceMeters: 100);
    await tester.pumpWidget(_host(s, DetailCard(item: item, onClose: () {}, onRemoveCamera: () {})));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Gibt es nicht mehr'), findsOneWidget);
  });

  testWidgets('ReportSheet offers the types and locks them without a location', (tester) async {
    final s = (await tester.runAsync(_services))!;
    await tester.pumpWidget(_host(
      s,
      ReportSheet(types: interimCatalog.types(), location: null, locating: false, message: null, onPick: (a, b) {}, onCancel: () {}),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Was möchtest du melden?'), findsOneWidget);
    expect(find.text('Stau'), findsOneWidget);
    expect(find.textContaining('Kein Standort verfügbar'), findsOneWidget);
  });

  testWidgets('SpeedLimitCard without a tapped spot asks to tap a road', (tester) async {
    final s = (await tester.runAsync(_services))!;
    await tester.pumpWidget(_host(
      s,
      SpeedLimitCard(service: null, spot: null, spotEnd: null, unit: SpeedUnit.kmh, locked: false, onSaved: () {}, onClose: () {}, onWantsEnd: (_) {}),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Tippe auf eine Straße'), findsOneWidget);
  });

  testWidgets('DriveView shows speed, limit, a warning and the one-tap tiles', (tester) async {
    final s = (await tester.runAsync(_services))!;
    final snap = DriveSnapshot(
      active: true,
      simulated: true,
      speedKmh: 97,
      heading: 130,
      limit: (value: 100, unit: SpeedUnit.kmh),
      speedState: SpeedState.ok,
      warnings: const [
        ActiveWarning(id: 'a', level: WarnLevel.first, kind: WarnKind.point, category: 'accident', label: 'Unfall', distanceM: 650, since: 0),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(430, 900));
    await tester.pumpWidget(AppScope(
      services: s,
      child: MaterialApp(
        theme: buildTheme(TnColors.dark),
        home: Scaffold(
          body: DriveView(
            snapshot: snap,
            unit: SpeedUnit.kmh,
            lockEnabled: true,
            reportTypes: const ['traffic', 'accident', 'construction', 'ice', 'fixedSpeedCamera', 'mobileSpeedCamera'],
            onReport: (_) {},
            onAnswer: (_) {},
            onMute: () {},
            onStop: () {},
            onEnableLock: () {},
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('97'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('Unfall'), findsWidgets);
    expect(find.text('in 650 m'), findsOneWidget);
    expect(find.text('Blitzer'), findsOneWidget); // the camera kinds sit behind one tile
    expect(find.text('SIMULATION – keine echte Fahrt'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('SpeedLimitCard: "Nachreichen" waits for the second end, then offers the value and sends the stretch', (tester) async {
    final s = (await tester.runAsync(_services))!;
    final calls = <String>[];
    final service = TnService(_Fake((method, args) {
      calls.add(method);
      return switch (method) {
        'lookupSpeedLimit' => {'status': 'notRecorded', 'source': 'offline'},
        'resolveRoadInterval' => {'road': 'Demostraße', 'lengthM': 420},
        'reportSpeedLimitInterval' => {'value': 50, 'unit': 'kmh', 'confirmations': 0},
        _ => null,
      };
    }));
    Spot? end;
    var wantsEnd = false;
    late StateSetter hostSet;
    await tester.pumpWidget(_host(
      s,
      StatefulBuilder(builder: (context, set) {
        hostSet = set;
        return SpeedLimitCard(
          key: const ValueKey('a'),
          service: service,
          spot: (lat: 48.2, lng: 11.6),
          spotEnd: end,
          unit: SpeedUnit.kmh,
          locked: false,
          onSaved: () {},
          onClose: () {},
          onWantsEnd: (v) => wantsEnd = v,
        );
      }),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Kein Tempolimit erfasst'), findsOneWidget);
    await tester.tap(find.text('Nachreichen'));
    await tester.pump();
    expect(wantsEnd, true);
    expect(find.textContaining('andere Ende'), findsOneWidget);
    // the map screen routes the next tap to the second end
    hostSet(() => end = (lat: 48.201, lng: 11.6));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Demostraße'), findsOneWidget);
    expect(find.text('Senden'), findsOneWidget);
    await tester.tap(find.text('50'));
    await tester.pump();
    await tester.tap(find.text('Senden'));
    await tester.pump();
    await tester.pump();
    expect(calls, containsAllInOrder(['lookupSpeedLimit', 'resolveRoadInterval', 'reportSpeedLimitInterval']));
    expect(find.textContaining('Gespeichert'), findsOneWidget);
  });
}

class _Fake implements TnBackend {
  _Fake(this.handler);
  final Object? Function(String, Map<String, Object?>) handler;
  @override
  Future<Object?> call(String method, Map<String, Object?> args) async => handler(method, args);
  @override
  Future<void> close() async {}
  @override
  Stream<Map<String, Object?>> get events => const Stream.empty();
  @override
  Future<void> startRealtime() async {}
  @override
  Future<void> stopRealtime() async {}
}
