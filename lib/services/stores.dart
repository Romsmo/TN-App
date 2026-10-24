import 'package:flutter/foundation.dart';
import 'package:tn_core/tn_core.dart';

import '../platform/platform.dart';

/// The local, non-secret settings in an ordinary app file (never in the Keychain: that survives a reinstall on iOS).
class SettingsStore extends ChangeNotifier {
  SettingsStore._(this._value, this._config);

  static Future<SettingsStore> open(BuildConfig config) async {
    final raw = await readSettingsFile();
    return SettingsStore._(parseSettings(raw, allowDisableDriveLock: config.allowDisableDriveLock), config);
  }

  Settings _value;
  final BuildConfig _config;

  Settings get value => _value;

  /// Changes some settings and writes the file. A change is visible at once; a failed write is not fatal.
  Future<void> update(Settings Function(Settings current) change) async {
    final next = change(_value);
    // the build decides whether the lock can be switched off at all
    _value = _config.allowDisableDriveLock ? next : next.copyWith(driveLockEnabled: true);
    notifyListeners();
    try {
      await writeSettingsFile(encodeSettings(_value));
    } catch (_) {}
  }

  /// "Lokale Daten löschen": back to the defaults (speed lock on, no server address).
  Future<void> reset() async {
    _value = defaultSettings;
    notifyListeners();
    await deleteSettingsFile();
  }
}

/// The access data the user typed under "Server verbinden", in the Keychain/Keystore.
class CredentialsStore extends ChangeNotifier {
  CredentialsStore._(this._secrets, this._cached, this._root);

  static Future<CredentialsStore> open() async {
    final secrets = userSecretStore();
    Credentials? cached;
    String? root;
    try {
      cached = parseCredentials(await secrets.get(credentialsKey));
    } catch (_) {}
    try {
      root = await secrets.get(joinRootKey);
      if (root != null && root.isEmpty) root = null;
    } catch (_) {}
    return CredentialsStore._(secrets, cached, root);
  }

  final SecretStore _secrets;
  Credentials? _cached;
  String? _root;

  Credentials? get value => _cached;

  /// The network's public root key from a join code (base64url), or null.
  String? get networkRootKey => _root;

  Future<void> set(Credentials credentials) async {
    await _secrets.set(credentialsKey, encodeCredentials(credentials));
    _cached = credentials;
    notifyListeners();
  }

  /// A join code: the app key and, when the code carries one, the root key, saved together (one change notification).
  Future<void> setJoined(Credentials credentials, {String? networkRootKey}) async {
    await _secrets.set(credentialsKey, encodeCredentials(credentials));
    if (networkRootKey != null) {
      await _secrets.set(joinRootKey, networkRootKey);
    } else {
      await _secrets.delete(joinRootKey);
    }
    _cached = credentials;
    _root = networkRootKey;
    notifyListeners();
  }

  Future<void> clear() async {
    await _secrets.delete(credentialsKey);
    await _secrets.delete(joinRootKey);
    _cached = null;
    _root = null;
    notifyListeners();
  }
}
