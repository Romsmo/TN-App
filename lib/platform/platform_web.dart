import 'package:flutter/foundation.dart';
import 'package:tn_core/tn_core.dart';

import '../services/demo_backend.dart';

/// The browser preview always answers from the demo backend; it is a development aid, never shipped.
const bool demoMode = true;

/// The browser preview shows the development aids (the simulated drive).
const bool devTools = true;

/// No Bluetooth in the browser preview.
DisplayTransport? createDisplayTransport() => null;

String? _settings;

Future<String?> readSettingsFile() async => _settings;

Future<void> writeSettingsFile(String content) async => _settings = content;

Future<void> deleteSettingsFile() async => _settings = null;

Future<void> deleteLibraryData() async {}

class _MemorySecrets implements SecretStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> get(String key) async => _m[key];
  @override
  Future<void> set(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

final _MemorySecrets _user = _MemorySecrets();

SecretStore userSecretStore() => _user;

Future<void> wipeLibrarySecrets() async {}

Future<TnBackend> createLibraryBackend(Map<String, Object?> options) async => DemoBackend();

bool get isMobile => defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android;
