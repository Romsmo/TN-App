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
  CredentialsStore._(this._secrets, this._cached);

  static Future<CredentialsStore> open() async {
    final secrets = userSecretStore();
    Credentials? cached;
    try {
      cached = parseCredentials(await secrets.get(credentialsKey));
    } catch (_) {}
    return CredentialsStore._(secrets, cached);
  }

  final SecretStore _secrets;
  Credentials? _cached;

  Credentials? get value => _cached;

  Future<void> set(Credentials credentials) async {
    await _secrets.set(credentialsKey, encodeCredentials(credentials));
    _cached = credentials;
    notifyListeners();
  }

  Future<void> clear() async {
    await _secrets.delete(credentialsKey);
    _cached = null;
    notifyListeners();
  }
}
