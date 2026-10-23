import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:tn_core/tn_core.dart';

import '../platform/platform.dart';
import 'app_config.dart';
import 'stores.dart';

/// Runs one library client for the current server and access settings and hands its state to the screens. The client is
/// rebuilt when the server address, the access data or the speed-camera option change, and after a reset.
class TnController extends ChangeNotifier {
  TnController({required this.settings, required this.credentials});

  final SettingsStore settings;
  final CredentialsStore credentials;

  TnConnection? _conn;
  void Function()? _unsub;
  String _key = '';
  bool _wifiOnly = true;
  Future<void> _chain = Future.value();
  bool _disposed = false;

  ConnectionSnapshot get snapshot => _conn?.snapshot ?? const ConnectionSnapshot();

  CameraPolicy? _policy;
  TnService? _policyFor;
  int _policyVersion = -1;

  /// The country policy for speed cameras as the library reports it (local, no network). Null until known. Read again
  /// when the stored data changes, because a stricter policy arrives with a sync.
  CameraPolicy? get policy => _policy;

  void _onConnection() {
    final snap = snapshot;
    final service = snap.service;
    if (service != _policyFor || snap.dataVersion != _policyVersion) {
      _policyFor = service;
      _policyVersion = snap.dataVersion;
      if (service == null) {
        _policy = null;
      } else {
        unawaited(service.getCameraPolicy().then<CameraPolicy?>((p) => p).catchError((_) => null).then((p) {
          if (_policyFor == service && !_disposed) {
            _policy = p;
            notifyListeners();
          }
        }));
      }
    }
    notifyListeners();
  }

  TnService? get service => snapshot.service;

  int get dataVersion => snapshot.dataVersion;

  Future<void> start() async {
    settings.addListener(_onSettings);
    credentials.addListener(_onSettings);
    await _rebuild(force: true);
  }

  void _onSettings() {
    final s = settings.value;
    if (s.dataWifiOnly != _wifiOnly) {
      _wifiOnly = s.dataWifiOnly;
      _conn?.setWifiOnly(_wifiOnly);
    }
    final key = _keyNow();
    if (key != _key) unawaited(_rebuild());
  }

  String _keyNow() {
    final s = settings.value;
    return [s.serverAddress ?? '', credentials.value?.toJson().toString() ?? '', s.camerasEnabled].join('|');
  }

  Future<void> _rebuild({bool force = false}) {
    // serialised: a rebuild waits for the one before it, and a stale one is skipped
    _chain = _chain.then((_) async {
      if (_disposed) return;
      final key = _keyNow();
      if (!force && key == _key) return;
      _key = key;
      final old = _conn;
      _unsub?.call();
      _conn = null;
      await old?.stop();
      final s = settings.value;
      _wifiOnly = s.dataWifiOnly;
      final options = buildClientOptions(
        serverAddress: s.serverAddress,
        credentials: credentials.value,
        config: buildConfig,
        cameraNamespaceEnabled: s.camerasEnabled,
      );
      final conn = TnConnection(
        createService: () async => TnService(await createLibraryBackend(options)),
        isOnWifi: _isOnWifi,
      )..setWifiOnly(_wifiOnly);
      _conn = conn;
      _unsub = conn.subscribe(_onConnection);
      notifyListeners();
      await conn.start();
    }).catchError((Object e) {
      if (kDebugMode) debugPrint('tn rebuild failed: $e');
    });
    return _chain;
  }

  static Future<bool> _isOnWifi() async {
    try {
      final r = await Connectivity().checkConnectivity();
      return r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return false; // no answer: cautious, as if on mobile data
    }
  }

  Future<void> syncNow({bool ignoreWifi = false}) async => _conn?.syncNow(ignoreWifi: ignoreWifi);

  void dismissRejected() => _conn?.dismissRejected();

  /// Deletes the library's database on this device (it is learned again from the server) and resets the app settings;
  /// the access data the user typed stays. With [identity] the device's credential and signing key go too, and the device
  /// registers anew.
  Future<void> resetLocal({required bool identity}) async {
    final completer = Completer<void>();
    _chain = _chain.then((_) async {
      try {
        final old = _conn;
        _unsub?.call();
        _conn = null;
        _key = '';
        await old?.stop(); // closes the client, so its database files can be removed
        if (identity) await wipeLibrarySecrets();
        await deleteLibraryData();
        await settings.reset(); // also: speed lock back on, server address empty
        completer.complete();
      } catch (e) {
        completer.completeError(e);
      }
    });
    try {
      await completer.future;
    } finally {
      // a failed deletion must not leave the app without a client
      await _rebuild(force: true);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    settings.removeListener(_onSettings);
    credentials.removeListener(_onSettings);
    _unsub?.call();
    unawaited(_conn?.stop());
    super.dispose();
  }
}
