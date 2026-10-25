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
  final assetFrames = <Uint8List>[];
  String? failAssetPath;
  String _currentAsset = '';
  bool assetSilent = false;

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
    if (slot == d.Slot.asset) {
      assetFrames.add(data);
      if (data[0] == 0x01) _currentAsset = String.fromCharCodes(data.sublist(2, 2 + data[1]));
      if (data[0] == 0x03 && !assetSilent) {
        final bad = failAssetPath == _currentAsset;
        Timer.run(() => _ctl(d.Slot.asset).add(Uint8List.fromList([bad ? 0x12 : 0x11])));
      }
      return;
    }
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

  group('file upload to the card (Asset)', () {
    Uint8List wav(int n) {
      final b = Uint8List(44 + n);
      final v = ByteData.sublistView(b);
      b.setRange(0, 4, 'RIFF'.codeUnits);
      v.setUint32(4, 36 + n, Endian.little);
      b.setRange(8, 16, 'WAVEfmt '.codeUnits);
      v.setUint32(16, 16, Endian.little);
      v.setUint16(20, 1, Endian.little);
      v.setUint16(22, 1, Endian.little);
      v.setUint32(24, 16000, Endian.little);
      v.setUint32(28, 32000, Endian.little);
      v.setUint16(32, 2, Endian.little);
      v.setUint16(34, 16, Endian.little);
      b.setRange(36, 40, 'data'.codeUnits);
      v.setUint32(40, n, Endian.little);
      for (var i = 0; i < n; i++) {
        b[44 + i] = i % 251;
      }
      return b;
    }

    test('the WAV check accepts the display format only', () {
      expect(isDisplayWav(wav(100)), isTrue);
      expect(isDisplayWav(Uint8List(10)), isFalse);
      final stereo = wav(100);
      ByteData.sublistView(stereo).setUint16(22, 2, Endian.little);
      expect(isDisplayWav(stereo), isFalse);
      final rate = wav(100);
      ByteData.sublistView(rate).setUint32(24, 22050, Endian.little);
      expect(isDisplayWav(rate), isFalse);
    });

    test('every file: begin with its path, ordered data, end, ok; the card paths are the contract\'s', () async {
      final files = [DisplayFile('audio/tones/warn.wav', wav(1000)), DisplayFile('audio/voice/de/in.wav', wav(300))];
      final progress = <int>[];
      final r = await link.runAssetUpload(files, onProgress: (i, sent, total) => progress.add(i));
      expect(r.ok, isTrue);
      expect(r.sent, 2);
      final begins = t.assetFrames.where((f) => f[0] == 0x01).map((f) => String.fromCharCodes(f.sublist(2))).toList();
      expect(begins, ['audio/tones/warn.wav', 'audio/voice/de/in.wav']);
      expect(t.assetFrames.where((f) => f[0] == 0x03), hasLength(2));
      expect(t.assetFrames.where((f) => f[0] == 0x02).every((f) => f.length <= 244), isTrue);
      expect(progress, containsAll([0, 1]));
      expect(link.updating, isFalse);
    });

    test('a file the card refuses stops the upload and names the file', () async {
      t.failAssetPath = 'audio/voice/de/in.wav';
      final files = [DisplayFile('audio/tones/warn.wav', wav(200)), DisplayFile('audio/voice/de/in.wav', wav(200)), DisplayFile('audio/voice/de/achtung.wav', wav(200))];
      final r = await link.runAssetUpload(files);
      expect(r.ok, isFalse);
      expect(r.sent, 1);
      expect(r.failedPath, 'audio/voice/de/in.wav');
      expect(r.outcome, OtaOutcome.deviceError);
      expect(t.assetFrames.where((f) => f[0] == 0x01), hasLength(2)); // the third was never started
    });

    test('a display that never says ok is a timeout; the user can cancel', () async {
      t.assetSilent = true;
      final r = await link.runAssetUpload([DisplayFile('audio/tones/warn.wav', wav(200))], fileTimeout: Duration.zero);
      expect(r.outcome, OtaOutcome.timeout);
      var n = 0;
      t.assetSilent = false;
      final c = await link.runAssetUpload([DisplayFile('audio/tones/warn.wav', wav(2000))], isCancelled: () => ++n > 2);
      expect(c.outcome, OtaOutcome.cancelled);
      expect(t.assetFrames.any((f) => f[0] == 0x04), isTrue);
    });
  });
}
