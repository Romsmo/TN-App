import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tn_core/tn_core.dart';
import 'package:tn_display_protocol/tn_display_protocol.dart' as d;

class WriteRecord {
  WriteRecord(this.slot, this.data, this.withResponse);
  final int slot;
  final Uint8List data;
  final bool withResponse;
}

class FakeTransport implements DisplayTransport {
  FakeTransport({d.DeviceInfo? info}) : info = info ?? const d.DeviceInfo(protoVersion: 1, fwVersion: '0.1.0', caps: 0x3f, width: 466, height: 466);
  d.DeviceInfo info;
  final writes = <WriteRecord>[];
  final calls = <String>[];
  final _conn = StreamController<bool>.broadcast();
  final _notify = <int, StreamController<Uint8List>>{};
  int connectFailures = 0;
  bool failStateWrites = false;

  StreamController<Uint8List> _ctl(int slot) => _notify.putIfAbsent(slot, () => StreamController<Uint8List>.broadcast());

  void notify(int slot, Uint8List data) => _ctl(slot).add(data);
  void drop() => _conn.add(false);

  @override
  Stream<DisplayFound> scan() => Stream.value(const DisplayFound(id: 'AA', name: 'BlitzerdeDsp'));
  @override
  Future<void> stopScan() async {}
  @override
  Future<void> connect(String id) async {
    calls.add('connect');
    if (connectFailures > 0) {
      connectFailures--;
      throw StateError('no');
    }
  }

  @override
  Future<void> disconnect() async => calls.add('disconnect');
  @override
  Stream<bool> get connection => _conn.stream;
  @override
  Future<int> negotiateMtu() async => 247;
  @override
  Future<Uint8List> read(int slot) async {
    calls.add('read$slot');
    return switch (slot) {
      d.Slot.deviceInfo => info.encode(),
      d.Slot.settings => const d.DeviceSettings(soundVolume: 10).encode(),
      d.Slot.uiConfig => const d.UiConfig().encode(),
      _ => Uint8List(0),
    };
  }

  @override
  Future<void> write(int slot, Uint8List data, {required bool withResponse}) async {
    if (slot == d.Slot.state && failStateWrites) throw StateError('write failed');
    writes.add(WriteRecord(slot, data, withResponse));
  }

  @override
  Stream<Uint8List> subscribe(int slot) => _ctl(slot).stream;
}

void main() {
  late FakeTransport t;
  late int now;
  late List<DisplayAction> actions;
  late DisplayLink link;
  DriveSnapshot snap = const DriveSnapshot(active: true, limit: (value: 50, unit: SpeedUnit.kmh));

  DisplayLink make() => DisplayLink(
        transport: t,
        input: () => DisplayInput(snapshot: snap, caps: link.caps, online: true, camerasEnabled: false, soundOnDisplay: true),
        settings: (caps) => displaySettingsFor(soundOnDisplay: true, voice: false, volume: 55, unit: SpeedUnit.kmh, warnOff: const [], camerasEnabled: false, caps: caps),
        nowMs: () => now,
        epochS: () => 1760000000 + now ~/ 1000,
        tzOffsetMin: () => 120,
        onAction: actions.add,
        delay: (_) async {},
      );

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    t = FakeTransport();
    now = 0;
    actions = [];
    snap = const DriveSnapshot(active: true, limit: (value: 50, unit: SpeedUnit.kmh));
    link = make();
  });

  test('the connect sequence: info, subscribe, time, complete settings, uiconfig, then State with stateSeq 1', () async {
    link.start('AA');
    await settle();
    expect(link.state, DisplayLinkState.ready);
    expect(link.caps.ota, isTrue);
    expect(link.mtu, 247);
    final slots = t.writes.map((w) => w.slot).toList();
    expect(slots, [d.Slot.time, d.Slot.settings]);
    final time = d.TimeSync.decode(t.writes[0].data);
    expect(time.tzOffsetMin, 120);
    expect(t.writes[0].withResponse, isTrue);
    final settings = d.DeviceSettings.decode(t.writes[1].data);
    expect(settings.soundVolume, 55); // the app's set replaces the display's own (10)
    expect(settings.soundEnabled, isTrue);
    expect(t.calls.indexOf('read${d.Slot.deviceInfo}'), lessThan(t.calls.indexOf('read${d.Slot.uiConfig}')));

    await link.tick();
    final state = t.writes.last;
    expect(state.slot, d.Slot.state);
    expect(state.withResponse, isFalse);
    final decoded = d.DisplayState.decode(state.data);
    expect(decoded.stateSeq, 1);
    expect(decoded.speedLimit, 50);
    await link.stop();
    expect(link.state, DisplayLinkState.off);
  });

  test('a display with another protocol major version gets no State and is disconnected', () async {
    t.info = const d.DeviceInfo(protoVersion: 2, fwVersion: '9.0.0', caps: 0x3f, width: 1, height: 1);
    link.start('AA');
    await settle();
    expect(link.state, DisplayLinkState.incompatible);
    expect(link.compat, DisplayCompat.appTooOld);
    await link.tick();
    expect(t.writes.where((w) => w.slot == d.Slot.state), isEmpty);
    expect(t.calls, contains('disconnect'));
  });

  test('after a drop the link reconnects, runs the sequence again and stateSeq starts at 1', () async {
    link.start('AA');
    await settle();
    await link.tick();
    now = 1000;
    snap = const DriveSnapshot(active: true, limit: (value: 60, unit: SpeedUnit.kmh));
    await link.tick();
    expect(d.DisplayState.decode(t.writes.last.data).stateSeq, 2);
    t.drop();
    await settle();
    expect(link.state, DisplayLinkState.ready);
    expect(t.calls.where((c) => c == 'connect').length, 2);
    now = 2000;
    await link.tick();
    expect(d.DisplayState.decode(t.writes.last.data).stateSeq, 1);
    await link.stop();
  });

  test('a failing connect is retried', () async {
    t.connectFailures = 2;
    link.start('AA');
    await settle();
    expect(link.state, DisplayLinkState.ready);
    expect(t.calls.where((c) => c == 'connect').length, 3);
    await link.stop();
  });

  test('events: a report becomes one action, a doubled one is ignored; settings from the display are kept', () async {
    link.start('AA');
    await settle();
    final report = cborReport(d.HazardType.accident);
    t.notify(d.Slot.event, report);
    t.notify(d.Slot.event, report);
    await settle();
    expect(actions.whereType<DisplayReport>().length, 1);
    t.notify(d.Slot.settings, const d.DeviceSettings(soundVolume: 33, soundEnabled: false).encode());
    await settle();
    expect(link.deviceSettings!.soundVolume, 33);
    await link.stop();
  });

  test('a failing State write never throws out of tick', () async {
    link.start('AA');
    await settle();
    t.failStateWrites = true;
    await link.tick();
    expect(link.lastError, isNotNull);
    expect(link.state, DisplayLinkState.ready);
    await link.stop();
  });

  test('pushSettings writes the complete set again', () async {
    link.start('AA');
    await settle();
    final before = t.writes.length;
    await link.pushSettings();
    expect(t.writes.length, before + 1);
    expect(t.writes.last.slot, d.Slot.settings);
    await link.stop();
  });
}

/// An Event notification as the display sends it: `{0: 1, 1: 1 (ReportSubmitted), 2: hazardType}`.
Uint8List cborReport(int hazardType) => d.cborEncode(<int, Object?>{0: 1, 1: d.EventTag.reportSubmitted, 2: hazardType});
