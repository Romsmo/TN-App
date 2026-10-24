import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tn_core/tn_core.dart';
import 'package:tn_display_protocol/tn_display_protocol.dart' as d;
import 'package:tnviewer/app_scope.dart';
import 'package:tnviewer/screens/display_screen.dart';
import 'package:tnviewer/services/app_config.dart';
import 'package:tnviewer/services/display_controller.dart';
import 'package:tnviewer/services/drive_controller.dart';
import 'package:tnviewer/services/legal.dart';
import 'package:tnviewer/services/location.dart';
import 'package:tnviewer/services/stores.dart';
import 'package:tnviewer/services/tn_controller.dart';
import 'package:tnviewer/ui/theme.dart';

class _Transport implements DisplayTransport {
  final writes = <(int, Uint8List)>[];
  final _conn = StreamController<bool>.broadcast();
  final _notify = <int, StreamController<Uint8List>>{};

  StreamController<Uint8List> _ctl(int slot) => _notify.putIfAbsent(slot, () => StreamController<Uint8List>.broadcast());

  @override
  Stream<DisplayFound> scan() => Stream.value(const DisplayFound(id: 'AA:BB', name: 'BlitzerdeDsp', rssi: -50));
  @override
  Future<void> stopScan() async {}
  @override
  Future<void> connect(String id) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Stream<bool> get connection => _conn.stream;
  @override
  Future<int> negotiateMtu() async => 247;
  @override
  Future<Uint8List> read(int slot) async => switch (slot) {
        d.Slot.deviceInfo => const d.DeviceInfo(protoVersion: 1, fwVersion: '0.1.0', caps: 0x3f, width: 466, height: 466).encode(),
        d.Slot.settings => const d.DeviceSettings().encode(),
        d.Slot.uiConfig => const d.UiConfig().encode(),
        _ => Uint8List(0),
      };
  @override
  Future<void> write(int slot, Uint8List data, {required bool withResponse}) async => writes.add((slot, data));
  @override
  Stream<Uint8List> subscribe(int slot) => _ctl(slot).stream;
}

Map<String, String> _table(String lang) => (jsonDecode(File('assets/texts/$lang.json').readAsStringSync()) as Map).cast<String, String>();

Future<AppServices> _services(DisplayTransport? transport) async {
  final texts = Texts(de: _table('de'), en: _table('en'), language: 'de');
  final settings = await SettingsStore.open(buildConfig);
  final credentials = await CredentialsStore.open();
  final tn = TnController(settings: settings, credentials: credentials);
  final drive = DriveController(tn: tn, settings: settings, texts: texts);
  final display = DisplayController(settings: settings, tn: tn, drive: drive, transport: transport);
  final legal = await LegalTexts.load();
  return AppServices(texts: texts, legal: legal, settings: settings, credentials: credentials, tn: tn, drive: drive, display: display, position: DevicePosition());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('without Bluetooth the screen says so and offers no search', (tester) async {
    final s = (await tester.runAsync(() => _services(null)))!;
    await tester.pumpWidget(AppScope(services: s, child: MaterialApp(theme: buildTheme(TnColors.light), home: const DisplayScreen())));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Bluetooth steht auf diesem Gerät nicht zur Verfügung.'), findsOneWidget);
    expect(find.text('Kein Display ausgewählt.'), findsOneWidget);
  });

  testWidgets('choose a display: it connects, the screen shows the device, the settings are written and the phone stays quiet', (tester) async {
    final t = _Transport();
    final s = (await tester.runAsync(() => _services(t)))!;
    await tester.pumpWidget(AppScope(services: s, child: MaterialApp(theme: buildTheme(TnColors.light), home: const DisplayScreen())));
    await tester.pump();
    expect(s.drive.phoneSoundAllowed(), isTrue); // not connected: the phone plays

    await tester.runAsync(() async {
      await s.display.choose(const DisplayFound(id: 'AA:BB', name: 'BlitzerdeDsp'));
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    await tester.pump();
    expect(s.settings.value.displayDeviceId, 'AA:BB');
    expect(s.display.connected, isTrue);
    expect(find.text('Verbunden mit BlitzerdeDsp.'), findsOneWidget);
    expect(find.text('Firmware 0.1.0'), findsOneWidget);
    expect(t.writes.map((w) => w.$1), containsAllInOrder([d.Slot.time, d.Slot.settings]));
    expect(s.drive.phoneSoundAllowed(), isFalse); // automatic: announcements on the display while it is connected

    // "Telefon": the phone plays again, and the display gets the new settings
    final before = t.writes.length;
    await tester.runAsync(() async {
      await s.settings.update((x) => x.copyWith(displaySound: DisplaySoundTarget.phone));
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    expect(s.drive.phoneSoundAllowed(), isTrue);
    expect(t.writes.length, greaterThan(before));
    expect(d.DeviceSettings.decode(t.writes.last.$2).soundEnabled, isFalse);

    await tester.runAsync(() async {
      await s.display.forget();
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    expect(s.display.connected, isFalse);
    expect(s.settings.value.displayDeviceId, isNull);
    s.display.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  test('display settings survive the settings file', () {
    const s = Settings(displayEnabled: true, displayDeviceId: 'AA', displayName: 'X', displaySound: DisplaySoundTarget.both, displayVolume: 30, displayVoice: true);
    final back = parseSettings(encodeSettings(s));
    expect(back.displayEnabled, isTrue);
    expect(back.displayDeviceId, 'AA');
    expect(back.displaySound, DisplaySoundTarget.both);
    expect(back.displayVolume, 30);
    expect(back.displayVoice, isTrue);
    final bad = parseSettings('{"displaySound":"nonsense","displayVolume":900}');
    expect(bad.displaySound, DisplaySoundTarget.auto);
    expect(bad.displayVolume, 100); // clamped
  });
}
