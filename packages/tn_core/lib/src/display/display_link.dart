import 'dart:async';
import 'dart:typed_data';

import 'package:tn_display_protocol/tn_display_protocol.dart' as d;

import 'display_feed.dart';
import 'display_update.dart';

/// A display found while scanning (it advertises the service UUID; the name is only a label, not an identity).
class DisplayFound {
  const DisplayFound({required this.id, required this.name, this.rssi});
  final String id;
  final String name;
  final int? rssi;
}

/// The Bluetooth side, kept small so the whole connection logic can be tested without a radio. The device implementation
/// (`universal_ble`) lives in the app.
abstract interface class DisplayTransport {
  /// Displays in range that advertise the service UUID of protocol v1.
  Stream<DisplayFound> scan();
  Future<void> stopScan();
  Future<void> connect(String id);
  Future<void> disconnect();

  /// `true` when connected, `false` when the link dropped.
  Stream<bool> get connection;

  /// Lets the OS negotiate the MTU; returns the value in force (best effort).
  Future<int> negotiateMtu();
  Future<Uint8List> read(int slot);
  Future<void> write(int slot, Uint8List data, {required bool withResponse});

  /// Notifications of a characteristic until the subscription is cancelled.
  Stream<Uint8List> subscribe(int slot);
}

enum DisplayLinkState {
  /// Not used (no display chosen, or switched off).
  off,

  /// Connecting, or connecting again after a drop.
  connecting,

  /// Connected and streaming.
  ready,

  /// The display speaks another protocol version; nothing is streamed. See [DisplayLink.compat].
  incompatible,
}

/// The connection to one display: the connect sequence of the contract, the State stream, the events, reconnecting. All decisions
/// about what to show are in [DisplayFeed]; this class moves bytes. Every error is contained: a missing or failing display never
/// affects the drive mode.
class DisplayLink {
  DisplayLink({
    required this.transport,
    required this.input,
    required this.settings,
    required this.nowMs,
    required this.epochS,
    required this.tzOffsetMin,
    this.onAction,
    this.onChange,
    Future<void> Function(Duration)? delay,
    DisplayFeed? feed,
    DisplayEventHandler? events,
  })  : _delay = delay ?? Future<void>.delayed,
        feed = feed ?? DisplayFeed(),
        _events = events ?? DisplayEventHandler();

  final DisplayTransport transport;

  /// The current drive input for the next State (read on every tick).
  final DisplayInput Function() input;

  /// The app's authoritative Settings for a display with these capabilities (written after every connect).
  final d.DeviceSettings Function(DisplayCaps caps) settings;
  final int Function() nowMs;
  final int Function() epochS;
  final int Function() tzOffsetMin;

  /// Something the display asked for (a report, a confirm, a settings change on the device).
  final void Function(DisplayAction action)? onAction;

  /// The state or the device data changed (for the screen).
  final void Function()? onChange;
  final Future<void> Function(Duration) _delay;
  final DisplayFeed feed;
  final DisplayEventHandler _events;

  DisplayLinkState state = DisplayLinkState.off;
  d.DeviceInfo? info;
  DisplayCaps caps = const DisplayCaps();
  DisplayCompat? compat;
  d.DeviceSettings? deviceSettings;
  d.UiConfig? uiConfig;
  int mtu = 23;
  int? lastHeartbeatMs;
  int? lastSentMs;
  int sentCount = 0;
  String? lastError;

  /// Connect attempts in a row that failed (the display is off, out of range, or already connected to another phone).
  int failedAttempts = 0;

  String? _id;
  int _generation = 0;
  final List<StreamSubscription<Object?>> _subs = [];
  bool _sending = false;

  /// A firmware transfer is running: no State packets go out meanwhile.
  bool updating = false;
  Completer<void>? _droppedNow;

  /// Connects to [id] and keeps the connection until [stop]; reconnects after a drop with a growing pause.
  void start(String id) {
    _id = id;
    final generation = ++_generation;
    _set(DisplayLinkState.connecting);
    unawaited(_run(generation));
  }

  Future<void> stop() async {
    _generation++;
    _id = null;
    final waiting = _droppedNow;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
    await _cancel();
    try {
      await transport.disconnect();
    } catch (_) {}
    info = null;
    compat = null;
    _set(DisplayLinkState.off);
  }

  Future<void> _cancel() async {
    // a copy: the connect loop may add subscriptions while a cancel is awaited
    final all = List<StreamSubscription<Object?>>.of(_subs);
    _subs.clear();
    for (final s in all) {
      await s.cancel();
    }
  }

  void _set(DisplayLinkState s) {
    state = s;
    onChange?.call();
  }

  bool _alive(int generation) => generation == _generation && _id != null;

  Future<void> _run(int generation) async {
    var pause = 2;
    while (_alive(generation)) {
      try {
        final dropped = _droppedNow = Completer<void>();
        await _connectOnce(_id!, generation, dropped);
        if (!_alive(generation)) return;
        if (state == DisplayLinkState.incompatible) return;
        pause = 2;
        failedAttempts = 0;
        await dropped.future; // until the link drops
        lastError = null;
      } catch (e) {
        lastError = e.runtimeType.toString(); // never the content
        failedAttempts++;
        onChange?.call();
      }
      if (!_alive(generation)) return;
      await _cancel();
      _set(DisplayLinkState.connecting);
      await _delay(Duration(seconds: pause));
      pause = pause >= 15 ? 15 : pause * 2;
    }
  }

  Future<void> _connectOnce(String id, int generation, Completer<void> dropped) async {
    await transport.connect(id);
    if (!_alive(generation)) return;
    _subs.add(transport.connection.listen((up) {
      if (!up && !dropped.isCompleted) dropped.complete();
    }));
    try {
      mtu = await transport.negotiateMtu();
    } catch (_) {}

    final got = d.DeviceInfo.decode(await transport.read(d.Slot.deviceInfo));
    info = got;
    caps = DisplayCaps.fromInfo(got);
    compat = displayCompat(got);
    if (compat != DisplayCompat.ok) {
      _set(DisplayLinkState.incompatible);
      try {
        await transport.disconnect();
      } catch (_) {}
      return;
    }

    _subs.add(transport.subscribe(d.Slot.event).listen(_onEvent));
    _subs.add(transport.subscribe(d.Slot.settings).listen(_onDeviceSettings));
    _subs.add(transport.subscribe(d.Slot.uiConfig).listen((b) {
      uiConfig = d.UiConfig.decode(b);
      onChange?.call();
    }));

    await transport.write(d.Slot.time, d.TimeSync(epochS(), tzOffsetMin()).encode(), withResponse: true);
    deviceSettings = d.DeviceSettings.decode(await transport.read(d.Slot.settings));
    final mine = settings(caps);
    await transport.write(d.Slot.settings, mine.encode(), withResponse: true);
    deviceSettings = mine;
    uiConfig = d.UiConfig.decode(await transport.read(d.Slot.uiConfig));

    feed.reset();
    _events.reset();
    sentCount = 0;
    _set(DisplayLinkState.ready);
  }

  void _onEvent(Uint8List bytes) {
    final e = d.DeviceEvent.tryDecode(bytes);
    if (e == null) return;
    final action = _events.handle(e, nowMs());
    if (action is DisplayHeartbeat) {
      lastHeartbeatMs = nowMs();
      onChange?.call();
    }
    if (action != null) onAction?.call(action);
  }

  void _onDeviceSettings(Uint8List bytes) {
    try {
      deviceSettings = d.DeviceSettings.decode(bytes);
    } on FormatException {
      return;
    }
    onChange?.call();
  }

  /// Called a few times a second while the drive runs (and every second otherwise): sends the next State if one is due.
  Future<void> tick() async {
    if (state != DisplayLinkState.ready || _sending || updating) return;
    _sending = true;
    try {
      final s = feed.next(input(), nowMs(), epochS: epochS());
      if (s == null) return;
      await transport.write(d.Slot.state, s.encode(), withResponse: false);
      lastSentMs = nowMs();
      sentCount++;
    } catch (e) {
      lastError = e.runtimeType.toString();
    } finally {
      _sending = false;
    }
  }

  /// Writes the complete Settings set again (after the user changed something in the app).
  Future<void> pushSettings() async {
    if (state != DisplayLinkState.ready) return;
    try {
      final mine = settings(caps);
      await transport.write(d.Slot.settings, mine.encode(), withResponse: true);
      deviceSettings = mine;
      onChange?.call();
    } catch (e) {
      lastError = e.runtimeType.toString();
    }
  }

  /// Writes the persistent feature switches (only used by the developer area).
  Future<void> writeUiConfig(d.UiConfig config) async {
    if (state != DisplayLinkState.ready) return;
    await transport.write(d.Slot.uiConfig, config.encode(), withResponse: true);
    uiConfig = config;
    onChange?.call();
  }

  /// Sends the time again (after the user changed the phone's time zone, or on request).
  Future<void> syncTime() async {
    if (state != DisplayLinkState.ready) return;
    try {
      await transport.write(d.Slot.time, d.TimeSync(epochS(), tzOffsetMin()).encode(), withResponse: true);
    } catch (e) {
      lastError = e.runtimeType.toString();
    }
  }

  /// Pushes a firmware image over the OTA characteristic as the contract describes: `begin`, wait for the first progress
  /// notification (the display erases the slot first), data frames paced like the reference tool, `end`, wait for the verdict. The
  /// caller has checked size and SHA-256 against the manifest. The display reboots after an accepted image, so the link drops by
  /// design; the reconnect loop brings it back and the caller reads the version again.
  Future<OtaResult> runOta(
    Uint8List image, {
    void Function(int sent, int total)? onProgress,
    bool Function()? isCancelled,
    Duration eraseTimeout = const Duration(seconds: 90),
    Duration verdictTimeout = const Duration(seconds: 45),
  }) async {
    if (state != DisplayLinkState.ready || updating) return const OtaResult(OtaOutcome.lostLink);
    updating = true;
    onChange?.call();
    final first = Completer<void>();
    final verdict = Completer<OtaResult>();
    final dropped = _droppedNow;
    late final StreamSubscription<Uint8List> sub;
    OtaResult? early;
    try {
      sub = transport.subscribe(d.Slot.ota).listen((b) {
        final n = d.OtaNotify.parse(b);
        if (n is d.OtaProgress) {
          if (!first.isCompleted) first.complete();
        } else if (n is d.OtaAccepted) {
          if (!verdict.isCompleted) verdict.complete(const OtaResult(OtaOutcome.accepted));
        } else if (n is d.OtaError) {
          if (!verdict.isCompleted) verdict.complete(OtaResult(OtaOutcome.deviceError, errorCode: n.code));
          if (!first.isCompleted) first.complete();
        }
      });
      Future<OtaResult?> failed() async {
        if (isCancelled?.call() == true) return const OtaResult(OtaOutcome.cancelled);
        if (verdict.isCompleted) return verdict.future;
        if (dropped != null && dropped.isCompleted) return const OtaResult(OtaOutcome.lostLink);
        return null;
      }

      await transport.write(d.Slot.ota, d.OtaFrames.beginForImage(image), withResponse: false);
      final erased = await Future.any<bool>([
        first.future.then((_) => true),
        _delay(eraseTimeout).then((_) => false),
        if (dropped != null) dropped.future.then((_) => false),
      ]);
      early = await failed();
      if (early == null && !erased) early = const OtaResult(OtaOutcome.timeout);
      if (early == null) {
        final chunk = (mtu - 3 < 244 ? mtu - 3 : 244) - 1;
        var sent = 0;
        var n = 0;
        for (final frame in d.OtaFrames.dataFrames(image, chunk: chunk < 19 ? 19 : chunk)) {
          early = await failed();
          if (early != null) break;
          await transport.write(d.Slot.ota, frame, withResponse: false);
          sent += frame.length - 1;
          onProgress?.call(sent, image.length);
          if (++n % 10 == 0) await _delay(const Duration(milliseconds: 40));
        }
        if (early == null) {
          await transport.write(d.Slot.ota, d.OtaFrames.end(), withResponse: false);
          early = await Future.any<OtaResult>([
            verdict.future,
            _delay(verdictTimeout).then((_) => const OtaResult(OtaOutcome.timeout)),
            if (dropped != null) dropped.future.then((_) => verdict.isCompleted ? const OtaResult(OtaOutcome.accepted) : const OtaResult(OtaOutcome.lostLink)),
          ]);
        }
      }
      final result = early;
      if (!result.ok && result.outcome != OtaOutcome.lostLink && result.outcome != OtaOutcome.deviceError) {
        try {
          await transport.write(d.Slot.ota, d.OtaFrames.abort(), withResponse: false);
        } catch (_) {}
      }
      return result;
    } catch (e) {
      lastError = e.runtimeType.toString();
      return const OtaResult(OtaOutcome.lostLink);
    } finally {
      try {
        await sub.cancel();
      } catch (_) {}
      updating = false;
      onChange?.call();
    }
  }

  /// Copies files to the display's card over the Asset characteristic: per file `begin` (path), paced data frames, `end`, wait for
  /// the display's `ok`; a pause between files (the card shares a bus with the screen). A file that fails stops the upload; a file
  /// that was cut off by a dropped link stays incomplete on the card and is overwritten by the next `begin`.
  Future<AssetUploadResult> runAssetUpload(
    List<DisplayFile> files, {
    void Function(int fileIndex, int sentBytes, int fileBytes)? onProgress,
    bool Function()? isCancelled,
    Duration fileTimeout = const Duration(seconds: 20),
  }) async {
    if (state != DisplayLinkState.ready || updating) return const AssetUploadResult(sent: 0, outcome: OtaOutcome.lostLink);
    updating = true;
    onChange?.call();
    final dropped = _droppedNow;
    var verdict = Completer<bool>();
    var sentFiles = 0;
    late final StreamSubscription<Uint8List> sub;
    try {
      sub = transport.subscribe(d.Slot.asset).listen((b) {
        final r = d.parseAssetNotify(b);
        if (r != null && !verdict.isCompleted) verdict.complete(r == d.AssetResult.ok);
      });
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        if (isCancelled?.call() == true) return AssetUploadResult(sent: sentFiles, failedPath: f.path, outcome: OtaOutcome.cancelled);
        verdict = Completer<bool>();
        await transport.write(d.Slot.asset, d.AssetFrames.begin(f.path), withResponse: false);
        final chunk = (mtu - 3 < 244 ? mtu - 3 : 244) - 1;
        var sent = 0;
        var n = 0;
        for (final frame in d.AssetFrames.dataFrames(f.bytes, chunk: chunk < 19 ? 19 : chunk)) {
          if (isCancelled?.call() == true || (dropped != null && dropped.isCompleted)) {
            try {
              await transport.write(d.Slot.asset, d.AssetFrames.abort(), withResponse: false);
            } catch (_) {}
            return AssetUploadResult(
              sent: sentFiles,
              failedPath: f.path,
              outcome: isCancelled?.call() == true ? OtaOutcome.cancelled : OtaOutcome.lostLink,
            );
          }
          await transport.write(d.Slot.asset, frame, withResponse: false);
          sent += frame.length - 1;
          onProgress?.call(i, sent, f.bytes.length);
          if (++n % 10 == 0) await _delay(const Duration(milliseconds: 40));
        }
        await transport.write(d.Slot.asset, d.AssetFrames.end(), withResponse: false);
        final ok = await Future.any<bool?>([
          verdict.future,
          _delay(fileTimeout).then((_) => null),
          if (dropped != null) dropped.future.then((_) => null),
        ]);
        if (ok != true) {
          return AssetUploadResult(sent: sentFiles, failedPath: f.path, outcome: ok == null ? OtaOutcome.timeout : OtaOutcome.deviceError);
        }
        sentFiles++;
        await _delay(const Duration(milliseconds: 250));
      }
      return AssetUploadResult(sent: sentFiles);
    } catch (e) {
      lastError = e.runtimeType.toString();
      return AssetUploadResult(sent: sentFiles, failedPath: 'link', outcome: OtaOutcome.lostLink);
    } finally {
      try {
        await sub.cancel();
      } catch (_) {}
      updating = false;
      onChange?.call();
    }
  }
}
