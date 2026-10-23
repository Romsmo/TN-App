import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tn_core/tn_core.dart';
import 'package:trafficnetwork_flutter/trafficnetwork_flutter.dart' as tn;

import '../services/demo_backend.dart';

/// Whether this build answers from the demo backend (development only: `--dart-define=TN_DEMO=true`).
const bool demoMode = bool.fromEnvironment('TN_DEMO');

Future<File> _settingsFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/settings.json');
}

Future<String?> readSettingsFile() async {
  try {
    final f = await _settingsFile();
    return await f.exists() ? await f.readAsString() : null;
  } catch (_) {
    return null;
  }
}

Future<void> writeSettingsFile(String content) async {
  final f = await _settingsFile();
  await f.writeAsString(content, flush: true);
}

Future<void> deleteSettingsFile() async {
  try {
    final f = await _settingsFile();
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

Future<Directory> _libraryDir() async {
  final dir = await getApplicationSupportDirectory();
  return Directory('${dir.path}/trafficnetwork');
}

/// "Lokale Daten löschen": the library's database folder. The client must be closed first.
Future<void> deleteLibraryData() async {
  try {
    final d = await _libraryDir();
    if (await d.exists()) await d.delete(recursive: true);
  } catch (_) {}
}

const FlutterSecureStorage _storage = FlutterSecureStorage(
  // not synced to iCloud, readable after the first unlock (a drive can start with the screen locked)
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
);

class _DeviceSecrets implements SecretStore {
  _DeviceSecrets({required this.prefixed});

  /// The library's own secrets use [sanitizeSecretKey]; the user's access data uses its plain key.
  final bool prefixed;

  String _key(String k) => prefixed ? sanitizeSecretKey(k) : k;

  @override
  Future<String?> get(String key) => _storage.read(key: _key(key));

  @override
  Future<void> set(String key, String value) => _storage.write(key: _key(key), value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: _key(key));
}

/// The store for the access data the user typed under "Server verbinden".
SecretStore userSecretStore() => _DeviceSecrets(prefixed: false);

/// "Geräteidentität zurücksetzen": removes everything the library wrote into the Keychain/Keystore, but not the access data
/// the user typed.
Future<void> wipeLibrarySecrets() async {
  try {
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(librarySecretPrefix)) await _storage.delete(key: key);
    }
  } catch (_) {}
}

class _LibrarySecureStore implements tn.SecureStore {
  final SecretStore _inner = _DeviceSecrets(prefixed: true);
  @override
  Future<String?> get(String key) => _inner.get(key);
  @override
  Future<void> set(String key, String value) => _inner.set(key, value);
  @override
  Future<void> delete(String key) => _inner.delete(key);
}

bool _initialized = false;

/// Creates the library client (or the demo backend) for these options.
Future<TnBackend> createLibraryBackend(Map<String, Object?> options) async {
  if (demoMode) return DemoBackend();
  if (!_initialized) {
    await tn.initialize();
    _initialized = true;
  }
  final dir = await _libraryDir();
  await dir.create(recursive: true);
  final client = await tn.TrafficNetworkClient.create(
    {...options, 'storagePath': dir.path},
    secureStore: _LibrarySecureStore(),
  );
  return _LibraryBackend(client);
}

class _LibraryBackend implements TnBackend {
  _LibraryBackend(this._client);
  final tn.TrafficNetworkClient _client;

  @override
  Future<Object?> call(String method, Map<String, Object?> args) async {
    try {
      return await _client.call(method, args);
    } on tn.TrafficNetworkException catch (e) {
      throw TnError(e.code, e.message);
    }
  }

  @override
  Stream<Map<String, Object?>> get events => _client.events;

  @override
  Future<void> startRealtime() => _client.startRealtime();

  @override
  Future<void> stopRealtime() => _client.stopRealtime();

  @override
  Future<void> close() => _client.close();
}

/// True on iOS and Android (the platforms the background location and the foreground service apply to).
bool get isMobile => defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android;
