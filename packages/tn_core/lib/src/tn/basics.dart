import 'dart:convert';

import 'types.dart';

// ---------------------------------------------------------------- server address

sealed class AddressResult {
  const AddressResult();
}

class AddressOk extends AddressResult {
  const AddressOk(this.url);
  final String url;
}

enum AddressProblem { empty, invalid, insecure, credentials }

class AddressError extends AddressResult {
  const AddressError(this.reason);
  final AddressProblem reason;
}

/// Cleans up what a user typed into "Server verbinden".
/// The library's own network stack ignores the platform's cleartext rules, so the app has to enforce HTTPS itself:
/// plain http is accepted only when [allowInsecure] is set (development builds, local test network).
AddressResult normalizeServerAddress(String input, {required bool allowInsecure}) {
  final text = input.trim();
  if (text.isEmpty) return const AddressError(AddressProblem.empty);

  final hasScheme = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*://').hasMatch(text);
  final candidate = hasScheme ? text : 'https://$text';

  if (RegExp(r'\s').hasMatch(candidate)) return const AddressError(AddressProblem.invalid);

  Uri url;
  try {
    url = Uri.parse(candidate);
  } catch (_) {
    return const AddressError(AddressProblem.invalid);
  }
  if (url.scheme != 'https' && url.scheme != 'http') return const AddressError(AddressProblem.invalid);
  if (url.host.isEmpty) return const AddressError(AddressProblem.invalid);
  if (url.userInfo.isNotEmpty) return const AddressError(AddressProblem.credentials);
  if (url.scheme == 'http' && !allowInsecure) return const AddressError(AddressProblem.insecure);

  final path = url.path.replaceFirst(RegExp(r'/+$'), '');
  // like the WHATWG URL parser, the default port of the scheme is not written out
  final defaultPort = url.scheme == 'https' ? 443 : 80;
  final host = url.hasPort && url.port != defaultPort ? '${url.host}:${url.port}' : url.host;
  return AddressOk('${url.scheme}://$host$path');
}

// ---------------------------------------------------------------- sync policy

/// Whether the app lets the library sync now. Live reports are tiny and always allowed; the static data packages are
/// the big download, and with "Wi-Fi only" they wait for Wi-Fi. The library cannot split the two, so the app decides
/// before it calls `tick`.
bool shouldSync({required bool wifiOnly, required bool onWifi, required int? bytesPending}) {
  if (!wifiOnly || onWifi) return true;
  return bytesPending == 0;
}

// ---------------------------------------------------------------- client options

/// Build-time configuration. Nothing in here is a secret; a public app key is public by design.
class BuildConfig {
  const BuildConfig({
    this.defaultNode,
    this.appClientId,
    this.appClientSecret,
    this.networkRootKey,
    this.mapStyleUrl,
    this.mapStyleUrlDark,
    this.allowDisableDriveLock = true,
    this.allowInsecureServer = false,
  });

  /// A server the app tries first, besides the discovery from the seeds.
  final String? defaultNode;

  /// A public app key (scope `device-registration`) that lets a fresh install register itself.
  final String? appClientId;
  final String? appClientSecret;

  /// Root key of the network (base64url public key). Without it a signed network configuration is ignored.
  final String? networkRootKey;

  /// A MapLibre style URL; there is deliberately no default (see docs/map-sources.md).
  final String? mapStyleUrl;
  final String? mapStyleUrlDark;

  /// Whether the user may switch the speed lock off at all.
  final bool allowDisableDriveLock;

  /// Plain `http` server addresses (development builds only).
  final bool allowInsecureServer;

  Credentials? get publicAppKey =>
      (appClientId?.isNotEmpty ?? false) && (appClientSecret?.isNotEmpty ?? false)
          ? AppCredentials(appClientId!, appClientSecret!)
          : null;
}

const String tnDomain = 'trafficnetwork.info';

/// Where a fresh install starts looking for servers (discovery). These hosts did not exist in DNS on 2026-10-22.
const List<String> seedServers = ['https://seed1.$tnDomain', 'https://seed2.$tnDomain'];

const String sourceRepoUrl = 'https://github.com/Romsmo/Trafficnetwork';
const String mapAttribution = '© OpenStreetMap contributors';
const int tickIntervalMs = 10000;

/// The library options for the current settings (without `storagePath`). A server the user entered is used directly
/// and alone (no discovery); otherwise the library discovers servers from the seeds.
Map<String, Object?> buildClientOptions({
  required String? serverAddress,
  required Credentials? credentials,
  required BuildConfig config,
  bool cameraNamespaceEnabled = false,
  String? networkRootKey,
}) {
  final options = <String, Object?>{};
  final node = config.defaultNode;
  if (serverAddress != null) {
    options['discovery'] = false;
    options['nodes'] = [serverAddress];
  } else if (node != null && node.isNotEmpty) {
    options['discovery'] = true;
    options['nodes'] = [node];
    options['seeds'] = [node, ...seedServers];
  } else {
    options['discovery'] = true;
    options['seeds'] = [...seedServers];
  }
  // The key from a join code wins over the one built in.
  final root = networkRootKey != null && networkRootKey.isNotEmpty ? networkRootKey : config.networkRootKey;
  if (root != null && root.isNotEmpty) options['networkRootKey'] = root;
  // Access the user typed wins; otherwise a build that is open to everyone registers the device with its public app key.
  final creds = credentials ?? config.publicAppKey;
  if (creds != null) options['credentials'] = creds.toJson();
  options['cameraNamespaceEnabled'] = cameraNamespaceEnabled;
  return options;
}

// ---------------------------------------------------------------- credentials

/// The access data the user typed is kept under its own name so a device reset leaves it alone.
const String credentialsKey = 'app_access';

/// The network's public root key that came with a join code (not a secret; kept next to the access data it belongs to).
const String joinRootKey = 'app_join_root';

Credentials? parseCredentials(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final o = jsonDecode(raw);
    if (o is! Map) return null;
    if (o['type'] == 'client' && o['clientId'] is String && o['clientSecret'] is String && (o['clientId'] as String).isNotEmpty && (o['clientSecret'] as String).isNotEmpty) {
      return ClientCredentials(o['clientId'] as String, o['clientSecret'] as String);
    }
    if (o['type'] == 'app' && o['appClientId'] is String && o['appClientSecret'] is String && (o['appClientId'] as String).isNotEmpty && (o['appClientSecret'] as String).isNotEmpty) {
      return AppCredentials(o['appClientId'] as String, o['appClientSecret'] as String);
    }
  } catch (_) {
    // fall through
  }
  return null;
}

String encodeCredentials(Credentials credentials) => jsonEncode(credentials.toJson());

// ---------------------------------------------------------------- secrets

/// Where secrets live: the Keychain on iOS, the Keystore on Android. Asynchronous, like the plugins behind it.
/// (The same shape the client library's own secret store has, so the app can hand one to the other.)
abstract interface class SecretStore {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
  Future<void> delete(String key);
}

/// Keys of the library's own secrets (device access, signing key) carry this prefix in the secret store, so "reset device
/// identity" can remove all of them and nothing else; the access data the user typed lives under [credentialsKey].
const String librarySecretPrefix = 'tn.';

/// A key the secret store accepts: letters, digits, ".", "-" and "_" only.
String sanitizeSecretKey(String key) => '$librarySecretPrefix${key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}';
