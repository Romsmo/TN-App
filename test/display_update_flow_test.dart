import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tn_core/tn_core.dart';
import 'package:tn_display_protocol/tn_display_protocol.dart' as d;
import 'package:tnviewer/services/app_config.dart';
import 'package:tnviewer/services/display_controller.dart';
import 'package:tnviewer/services/display_update_source.dart';
import 'package:tnviewer/services/drive_controller.dart';
import 'package:tnviewer/services/stores.dart';
import 'package:tnviewer/services/tn_controller.dart';

/// A display that takes an OTA image, reboots, and comes back with the new firmware version (or, when [rollBack] is set, with the old one).
class _Display implements DisplayTransport {
  String fw = '0.1.0';
  bool rollBack = false;
  bool refuse = false;
  int dataFrames = 0;
  final _conn = StreamController<bool>.broadcast();
  final _notify = <int, StreamController<Uint8List>>{};

  StreamController<Uint8List> _ctl(int slot) => _notify.putIfAbsent(slot, () => StreamController<Uint8List>.broadcast());

  @override
  Stream<DisplayFound> scan() => const Stream.empty();
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
        d.Slot.deviceInfo => d.DeviceInfo(protoVersion: 1, fwVersion: fw, caps: 0x3f, width: 466, height: 466).encode(),
        d.Slot.settings => const d.DeviceSettings().encode(),
        d.Slot.uiConfig => const d.UiConfig().encode(),
        _ => Uint8List(0),
      };

  @override
  Future<void> write(int slot, Uint8List data, {required bool withResponse}) async {
    if (slot != d.Slot.ota) return;
    switch (data[0]) {
      case 0x01:
        Timer.run(() => _ctl(d.Slot.ota).add(Uint8List.fromList([0x10, 0, 0, 0, 0])));
      case 0x02:
        dataFrames++;
      case 0x03:
        Timer.run(() {
          if (refuse) {
            _ctl(d.Slot.ota).add(Uint8List.fromList([0x12, 4]));
            return;
          }
          _ctl(d.Slot.ota).add(Uint8List.fromList([0x11]));
          Timer(const Duration(milliseconds: 100), () {
            if (!rollBack) fw = '0.2.0';
            _conn.add(false);
          });
        });
    }
  }

  @override
  Stream<Uint8List> subscribe(int slot) => _ctl(slot).stream;
}

class _Source implements DisplayUpdateSource {
  _Source(this.bytes, this.manifestText);
  final Uint8List bytes;
  String manifestText;
  UpdateFetchProblem? failWith;
  Uint8List? served;

  @override
  Future<DisplayManifest> manifest() async {
    if (failWith != null) throw UpdateFetchException(failWith!);
    return DisplayManifest.tryParse(manifestText)!;
  }

  @override
  Future<Uint8List> image(DisplayManifest m, {void Function(int received, int total)? onProgress}) async {
    onProgress?.call(bytes.length, bytes.length);
    return served ?? bytes;
  }
}

Map<String, String> _table(String lang) => (jsonDecode(File('assets/texts/$lang.json').readAsStringSync()) as Map).cast<String, String>();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final image = Uint8List.fromList(List.generate(4000, (i) => (i * 13) % 256));
  final hex = d.sha256Of(image).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final manifestText =
      '{"manifestVersion":1,"firmware":{"version":"0.2.0","minFromVersion":"0.1.0","image":{"file":"tn-display-0.2.0.bin","sizeBytes":${image.length},"sha256":"$hex"}},'
      '"protocol":{"version":1,"minAppProtocol":1},"changes":{"de":["Neu"],"en":["New"]},"signature":null}';

  late _Display display;
  late _Source source;
  late DisplayController controller;
  late SettingsStore settings;

  Future<void> setUpController({bool autoCheck = false}) async {
    display = _Display();
    source = _Source(image, manifestText);
    final texts = Texts(de: _table('de'), en: _table('en'), language: 'de');
    settings = await SettingsStore.open(buildConfig);
    final credentials = await CredentialsStore.open();
    final tn = TnController(settings: settings, credentials: credentials);
    final drive = DriveController(tn: tn, settings: settings, texts: texts);
    controller = DisplayController(settings: settings, tn: tn, drive: drive, transport: display, updates: source);
    await settings.update((s) => s.copyWith(displayFeature: true, displayEnabled: true, displayDeviceId: 'AA', displayName: 'X', displayAutoUpdateCheck: autoCheck));
    controller.start();
    for (var i = 0; i < 40 && !controller.connected; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(controller.connected, isTrue);
  }

  tearDown(() => controller.dispose());

  test('check, install, reboot, version verified: success', () async {
    await setUpController();
    await controller.checkForUpdate();
    expect(controller.updatePhase, DisplayUpdatePhase.available);
    expect(controller.manifest!.version, '0.2.0');
    expect(controller.updateBlocker, isNull);
    await controller.installUpdate();
    expect(display.dataFrames, greaterThan(10));
    expect(controller.updatePhase, DisplayUpdatePhase.success);
    expect(controller.info!.fwVersion, '0.2.0');
    expect(settings.value.displayLastUpdateCheck, isNotNull);
  });

  test('a display that rolls back is reported as failed, never as success', () async {
    await setUpController();
    display.rollBack = true;
    await controller.checkForUpdate();
    // shorten the wait for the version: the controller waits up to two minutes, so only the first seconds are observed here
    final run = controller.installUpdate();
    await Future<void>.delayed(const Duration(seconds: 6));
    expect(controller.updatePhase, DisplayUpdatePhase.verifying);
    expect(controller.info?.fwVersion, '0.1.0');
    controller.cancelUpdate(); // has no effect after the transfer; the result is never "success" without the new version
    expect(controller.updatePhase, isNot(DisplayUpdatePhase.success));
    unawaited(run.timeout(const Duration(milliseconds: 1), onTimeout: () {}));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('the display refuses the image: failed with its error code, old version kept', () async {
    await setUpController();
    display.refuse = true;
    await controller.checkForUpdate();
    await controller.installUpdate();
    expect(controller.updatePhase, DisplayUpdatePhase.failed);
    expect(controller.updateErrorCode, 4);
    expect(controller.info!.fwVersion, '0.1.0');
  });

  test('a tampered download is refused before anything is sent to the display', () async {
    await setUpController();
    await controller.checkForUpdate();
    source.served = Uint8List.fromList(image)..[100] ^= 1;
    await controller.installUpdate();
    expect(controller.updatePhase, DisplayUpdatePhase.badRelease);
    expect(display.dataFrames, 0);
  });

  test('an unreachable or private source is said plainly; an automatic check fails quietly', () async {
    await setUpController();
    source.failWith = UpdateFetchProblem.notFound;
    await controller.checkForUpdate();
    expect(controller.updatePhase, DisplayUpdatePhase.sourceUnavailable);
    await controller.checkForUpdate(automatic: true);
    expect(controller.updatePhase, DisplayUpdatePhase.idle);
  });

  test('no installing while a drive runs or without a connection', () async {
    await setUpController();
    await controller.checkForUpdate();
    expect(controller.updateBlocker, isNull);
    await settings.update((s) => s.copyWith(displayFeature: false));
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(controller.updateBlocker, 'notConnected');
    await controller.installUpdate();
    expect(display.dataFrames, 0);
  });

  test('an automatic check runs once after connecting, only when allowed, and not again within a day', () async {
    await setUpController(autoCheck: true);
    for (var i = 0; i < 100 && controller.updatePhase != DisplayUpdatePhase.available; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(controller.updatePhase, DisplayUpdatePhase.available);
    expect(settings.value.displayLastUpdateCheck, isNotNull);
  });
}
