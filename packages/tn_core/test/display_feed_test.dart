import 'package:test/test.dart';
import 'package:tn_core/tn_core.dart';
import 'package:tn_display_protocol/tn_display_protocol.dart' as d;

const caps = DisplayCaps(audio: true, sd: true, speedcamBuild: true, ota: true, rtc: true);

ActiveWarning warn(String id, String category, {WarnLevel level = WarnLevel.first, int? dist = 400}) =>
    ActiveWarning(id: id, level: level, kind: WarnKind.point, category: category, label: category, distanceM: dist, since: 0);

DisplayInput input({
  DriveSnapshot snapshot = const DriveSnapshot(active: true),
  DisplayCaps c = caps,
  bool cameras = false,
  bool sound = true,
}) =>
    DisplayInput(snapshot: snapshot, caps: c, online: true, camerasEnabled: cameras, soundOnDisplay: sound);

void main() {
  group('mapping', () {
    test('every app category with a display counterpart maps to its id, others to null', () {
      expect(displayHazardId('accident'), d.HazardType.accident);
      expect(displayHazardId('fixedSpeedCamera'), d.HazardType.fixedSpeedCamera);
      expect(displayHazardId('cameras'), isNull);
      expect(displayHazardId('roadworks-unknown'), isNull);
      expect(appReportTypeFor(d.HazardType.ice), 'ice');
      expect(appReportTypeFor(d.HazardType.mobileSpeedCamera), isNull);
    });

    test('the filter never switches camera categories on without the user, the country rule or the firmware code', () {
      expect(displayFilterBits(warnOff: const [], camerasEnabled: false, caps: caps), 0x7e0);
      expect(displayFilterBits(warnOff: const [], camerasEnabled: true, caps: caps), 0x7ff);
      expect(displayFilterBits(warnOff: const [], camerasEnabled: true, caps: const DisplayCaps()), 0x7e0);
      expect(displayFilterBits(warnOff: const ['ice', 'cameras'], camerasEnabled: true, caps: caps), 0x7ff & ~(1 << 6) & ~0x1f);
    });

    test('settings: complete set, voice only with a card, sound only with audio, volume clamped', () {
      final s = displaySettingsFor(soundOnDisplay: true, voice: true, volume: 150, unit: SpeedUnit.mph, warnOff: const [], camerasEnabled: false, caps: caps);
      expect(s.soundEnabled, isTrue);
      expect(s.soundMode, d.AudioMode.voice);
      expect(s.soundVolume, 100);
      expect(s.useMph, isTrue);
      final n = displaySettingsFor(soundOnDisplay: true, voice: true, volume: 40, unit: SpeedUnit.kmh, warnOff: const [], camerasEnabled: false, caps: const DisplayCaps());
      expect(n.soundEnabled, isFalse);
      expect(n.soundMode, d.AudioMode.tones);
      expect(d.DeviceSettings.decode(s.encode()).soundVolume, 100);
    });

    test('protocol compatibility', () {
      expect(displayCompat(const d.DeviceInfo(protoVersion: 1, fwVersion: '0.1.0', caps: 0, width: 466, height: 466)), DisplayCompat.ok);
      expect(displayCompat(const d.DeviceInfo(protoVersion: 2, fwVersion: '1.0.0', caps: 0, width: 1, height: 1)), DisplayCompat.appTooOld);
      expect(displayCompat(const d.DeviceInfo(protoVersion: 0, fwVersion: '', caps: 0, width: 1, height: 1)), DisplayCompat.displayTooOld);
    });
  });

  group('the State stream', () {
    test('stateSeq starts at 1, rises, and a reconnect starts again at 1', () {
      final f = DisplayFeed();
      final a = f.next(input(), 0, epochS: 100)!;
      expect(a.stateSeq, 1);
      final b = f.next(input(snapshot: const DriveSnapshot(active: true, limit: (value: 50, unit: SpeedUnit.kmh))), 600, epochS: 100)!;
      expect(b.stateSeq, 2);
      expect(b.speedLimit, 50);
      f.reset();
      expect(f.next(input(), 700, epochS: 100)!.stateSeq, 1);
    });

    test('unchanged content waits for the keep-alive (below 5 s); a change is not sent faster than twice a second', () {
      final f = DisplayFeed();
      expect(f.next(input(), 0, epochS: 1), isNotNull);
      expect(f.next(input(), 1000, epochS: 1), isNull);
      expect(f.next(input(), 3999, epochS: 1), isNull);
      final ka = f.next(input(), 4000, epochS: 1);
      expect(ka, isNotNull);
      final changed = input(snapshot: const DriveSnapshot(active: true, limit: (value: 70, unit: SpeedUnit.kmh)));
      expect(f.next(changed, 4100, epochS: 1), isNull); // too soon after the last packet
      expect(f.next(changed, 4500, epochS: 1)!.speedLimit, 70);
    });

    test('every packet fits the wire limit and decodes back', () {
      final f = DisplayFeed();
      final s = f.next(
        input(
          snapshot: DriveSnapshot(
            active: true,
            limit: (value: 30, unit: SpeedUnit.mph),
            warnings: [warn('a', 'accident', dist: 350)],
            prompt: const DrivePrompt(id: 'p', hazardType: 'accident', since: 0),
          ),
        ),
        0,
        epochS: 1760000000,
      )!;
      final bytes = s.encode();
      expect(bytes.length, lessThanOrEqualTo(d.maxPayloadBytes));
      final back = d.DisplayState.decode(bytes);
      expect(back.speedLimit, 30);
      expect(back.useMph, isTrue);
      expect(back.hazardType, d.HazardType.accident);
      expect(back.hazardDistanceM, 350);
      expect(back.confirmPromptActive, isTrue);
    });

    test('the nearest, second-stage hazard wins; a zone shows no distance', () {
      final f = DisplayFeed();
      final s = f.next(
        input(
          snapshot: DriveSnapshot(active: true, warnings: [
            warn('far', 'traffic', dist: 900),
            warn('near', 'ice', dist: 200),
            warn('second', 'construction', level: WarnLevel.second, dist: 600),
          ]),
        ),
        0,
        epochS: 1,
      )!;
      expect(s.hazardType, d.HazardType.construction);
      final z = DisplayFeed().next(
        input(
          snapshot: const DriveSnapshot(active: true, warnings: [
            ActiveWarning(id: 'z', level: WarnLevel.first, kind: WarnKind.zone, category: 'traffic', label: 'z', distanceM: null, since: 0),
          ]),
        ),
        0,
        epochS: 1,
      )!;
      expect(z.hazardActive, isTrue);
      expect(z.hazardDistanceM, isNull);
    });

    test('camera hazards are never sent unless cameras are on and the firmware has the camera code', () {
      final snap = DriveSnapshot(active: true, warnings: [warn('c', 'fixedSpeedCamera')]);
      expect(DisplayFeed().next(input(snapshot: snap), 0, epochS: 1)!.hazardActive, isFalse);
      expect(DisplayFeed().next(input(snapshot: snap, cameras: true), 0, epochS: 1)!.hazardType, d.HazardType.fixedSpeedCamera);
      expect(DisplayFeed().next(input(snapshot: snap, cameras: true, c: const DisplayCaps(audio: true)), 0, epochS: 1)!.hazardActive, isFalse);
    });

    test('an unknown category is not sent', () {
      final snap = DriveSnapshot(active: true, warnings: [warn('x', 'something-new')]);
      expect(DisplayFeed().next(input(snapshot: snap), 0, epochS: 1)!.hazardActive, isFalse);
    });

    test('the audio cue: new seq per announcement, held for the next packets, then dropped; none without audio or when muted', () {
      final f = DisplayFeed();
      final first = DriveSnapshot(active: true, warnings: [warn('a', 'accident', dist: 400)]);
      final p1 = f.next(input(snapshot: first), 0, epochS: 1)!;
      expect(p1.audioCue!.seq, 1);
      expect(p1.audioCue!.event, d.AudioEvent.hazardApproach);
      // the same warning again: the same cue (same seq) stays in the following packets
      final nearer = DriveSnapshot(active: true, warnings: [warn('a', 'accident', dist: 380)]);
      final p2 = f.next(input(snapshot: nearer), 600, epochS: 1)!;
      expect(p2.audioCue!.seq, 1);
      // second stage: a new announcement
      final second = DriveSnapshot(active: true, warnings: [warn('a', 'accident', level: WarnLevel.second, dist: 100)]);
      final p3 = f.next(input(snapshot: second), 1200, epochS: 1)!;
      expect(p3.audioCue!.seq, 2);
      expect(p3.audioCue!.event, d.AudioEvent.hazardImminent);
      // after the hold time the cue is gone
      final p4 = f.next(input(snapshot: DriveSnapshot(active: true, warnings: [warn('a', 'accident', level: WarnLevel.second, dist: 50)])), 3000, epochS: 1)!;
      expect(p4.audioCue, isNull);

      expect(DisplayFeed().next(input(snapshot: first, sound: false), 0, epochS: 1)!.audioCue, isNull);
      expect(DisplayFeed().next(input(snapshot: first, c: const DisplayCaps()), 0, epochS: 1)!.audioCue, isNull);
      final muted = DriveSnapshot(active: true, muted: true, warnings: [warn('a', 'accident')]);
      expect(DisplayFeed().next(input(snapshot: muted), 0, epochS: 1)!.audioCue, isNull);
    });

    test('the confirm prompt is announced once and stays set while the prompt lasts', () {
      final f = DisplayFeed();
      const prompt = DrivePrompt(id: 'p', hazardType: 'accident', since: 0);
      final a = f.next(input(snapshot: const DriveSnapshot(active: true, prompt: prompt)), 0, epochS: 1)!;
      expect(a.confirmPromptActive, isTrue);
      expect(a.audioCue!.event, d.AudioEvent.confirmPrompt);
      final b = f.next(input(snapshot: const DriveSnapshot(active: true, prompt: prompt, speedKmh: 40)), 3000, epochS: 1)!;
      expect(b.confirmPromptActive, isTrue);
      expect(b.audioCue, isNull);
    });
  });

  group('events from the display', () {
    final h = DisplayEventHandler();
    setUp(h.reset);

    test('a report becomes one app report; a doubled notification does not make a second', () {
      const e = d.DeviceEvent(d.EventTag.reportSubmitted, hazardType: d.HazardType.accident);
      final a = h.handle(e, 1000) as DisplayReport;
      expect(a.reportType, 'accident');
      expect(h.handle(e, 1500), isNull);
      expect(h.handle(e, 5000), isA<DisplayReport>());
    });

    test('a camera category never becomes a report; unknown tags are dropped', () {
      expect(h.handle(const d.DeviceEvent(d.EventTag.reportSubmitted, hazardType: d.HazardType.fixedSpeedCamera), 0), isNull);
      expect(h.handle(const d.DeviceEvent(d.EventTag.reportPressed), 0), isNull);
      expect(h.handle(const d.DeviceEvent(99), 0), isNull);
    });

    test('confirm, settings and heartbeat', () {
      expect((h.handle(const d.DeviceEvent(d.EventTag.confirmResponse, seen: true), 0) as DisplayConfirm).seen, isTrue);
      expect((h.handle(const d.DeviceEvent(d.EventTag.settingsFilterChanged, filterBits: 0x21), 0) as DisplaySettingsChanged).filterBits, 0x21);
      expect((h.handle(const d.DeviceEvent(d.EventTag.heartbeat, uptimeS: 30), 0) as DisplayHeartbeat).uptimeS, 30);
    });
  });
}
