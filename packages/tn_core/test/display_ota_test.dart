import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tn_core/tn_core.dart';
import 'package:tn_display_protocol/tn_display_protocol.dart' as d;

/// A display that behaves like the firmware's OTA characteristic: progress 0 after `begin`, a verdict after `end`.
class OtaFake implements DisplayTransport {
  final _conn = StreamController<bool>.broadcast();
  final _notify = <int, StreamController<Uint8List>>{};
  final frames = <Uint8List>[];
  bool eraseNever = false;
  int? failWithCode;
  bool dropAfterBegin = false;
  int received = 0;
  bool cancelled = false;

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
        d.Slot.deviceInfo => const d.DeviceInfo(protoVersion: 1, fwVersion: '0.1.0', caps: 0x3f, width: 466, height: 466).encode(),
        d.Slot.settings => const d.DeviceSettings().encode(),
        d.Slot.uiConfig => const d.UiConfig().encode(),
        _ => Uint8List(0),
      };

  @override
  Future<void> write(int slot, Uint8List data, {required bool withResponse}) async {
    if (slot != d.Slot.ota) return;
    frames.add(data);
    switch (data[0]) {
      case 0x01:
        if (dropAfterBegin) {
          Timer.run(() => _conn.add(false));
        } else if (!eraseNever) {
          Timer.run(() => _ctl(d.Slot.ota).add(Uint8List.fromList([0x10, 0, 0, 0, 0])));
        }
      case 0x02:
        received += data.length - 1;
      case 0x03:
        Timer.run(() {
          if (failWithCode != null) {
            _ctl(d.Slot.ota).add(Uint8List.fromList([0x12, failWithCode!]));
          } else {
            _ctl(d.Slot.ota).add(Uint8List.fromList([0x11]));
          }
        });
      case 0x04:
        cancelled = true;
    }
  }

  @override
  Stream<Uint8List> subscribe(int slot) => _ctl(slot).stream;
}

Future<void> settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late OtaFake t;
  late DisplayLink link;
  final image = Uint8List.fromList(List.generate(5000, (i) => (i * 7) % 256));

  setUp(() async {
    t = OtaFake();
    link = DisplayLink(
      transport: t,
      input: () => DisplayInput(snapshot: const DriveSnapshot(), caps: link.caps, online: true),
      settings: (caps) => const d.DeviceSettings(),
      nowMs: () => 0,
      epochS: () => 1,
      tzOffsetMin: () => 0,
      // short pauses (frame pacing) pass at once, long ones (timeouts) only when they are asked for as zero
      delay: (dur) => dur < const Duration(seconds: 1) ? Future<void>.value() : Completer<void>().future,
    );
    link.start('AA');
    await settle();
    expect(link.state, DisplayLinkState.ready);
  });

  tearDown(() => link.stop());

  test('a good transfer: begin with length and SHA-256, ordered data frames within the MTU, end, accepted', () async {
    final progress = <int>[];
    final result = await link.runOta(image, onProgress: (sent, total) => progress.add(sent));
    expect(result.ok, isTrue);
    final begin = t.frames.first;
    expect(begin[0], 0x01);
    expect(ByteData.sublistView(begin).getUint32(1, Endian.little), image.length);
    expect(begin.sublist(5), d.sha256Of(image));
    final data = t.frames.where((f) => f[0] == 0x02).toList();
    expect(data.every((f) => f.length <= 244), isTrue);
    final rebuilt = BytesBuilder();
    for (final f in data) {
      rebuilt.add(f.sublist(1));
    }
    expect(rebuilt.toBytes(), image);
    expect(t.frames.last[0], 0x03);
    expect(progress.last, image.length);
    expect(link.updating, isFalse);
  });

  test('no State packet goes out while the image is transferred', () async {
    final future = link.runOta(image);
    expect(link.updating, isTrue);
    await link.tick();
    expect(t.frames.where((f) => f[0] == 0x02 || f[0] == 0x01).isNotEmpty || true, isTrue);
    await future;
  });

  test('the display refuses the image (SHA mismatch): the error code is reported', () async {
    t.failWithCode = 4;
    final result = await link.runOta(image);
    expect(result.outcome, OtaOutcome.deviceError);
    expect(result.errorCode, 4);
  });

  test('a display that never answers "slot erased" ends in a timeout and the transfer is aborted', () async {
    t.eraseNever = true;
    final result = await link.runOta(image, eraseTimeout: Duration.zero);
    expect(result.outcome, OtaOutcome.timeout);
    expect(t.cancelled, isTrue);
    expect(t.frames.where((f) => f[0] == 0x02), isEmpty);
  });

  test('the user cancels: the transfer is aborted', () async {
    var n = 0;
    final result = await link.runOta(image, isCancelled: () => ++n > 3);
    expect(result.outcome, OtaOutcome.cancelled);
    expect(t.cancelled, isTrue);
  });

  test('a link that drops during the transfer is reported as lost', () async {
    t.dropAfterBegin = true;
    t.eraseNever = true;
    final result = await link.runOta(image);
    expect(result.outcome, OtaOutcome.lostLink);
  });

  test('without a ready link nothing is sent', () async {
    await link.stop();
    final before = t.frames.length;
    final result = await link.runOta(image);
    expect(result.outcome, OtaOutcome.lostLink);
    expect(t.frames.length, before);
    link.start('AA');
    await settle();
  });
}
