import 'package:tn_core/tn_core.dart';

/// Build-time configuration, given with `--dart-define`. Nothing in here is a secret: the values end up in the app and
/// anyone can read them. Real values are entered by the operator, never committed (see docs/build-config.md).
///
///   TN_DEFAULT_NODE            a server the app tries first (besides discovery from the seeds)
///   TN_APP_CLIENT_ID/SECRET    a public app key (scope `device-registration`) so a fresh install can register itself
///   TN_NETWORK_ROOT_KEY        the network's public root key (base64url)
///   MAP_STYLE_URL(_DARK)       a MapLibre style URL; there is deliberately no default
///   ALLOW_DISABLE_DRIVE_LOCK   `false` removes the option to switch the speed lock off (cautious review build)
///   ALLOW_INSECURE_SERVER      `true` accepts plain http server addresses (development only)
const BuildConfig buildConfig = BuildConfig(
  defaultNode: String.fromEnvironment('TN_DEFAULT_NODE'),
  appClientId: String.fromEnvironment('TN_APP_CLIENT_ID'),
  appClientSecret: String.fromEnvironment('TN_APP_CLIENT_SECRET'),
  networkRootKey: String.fromEnvironment('TN_NETWORK_ROOT_KEY'),
  mapStyleUrl: String.fromEnvironment('MAP_STYLE_URL'),
  mapStyleUrlDark: String.fromEnvironment('MAP_STYLE_URL_DARK'),
  allowDisableDriveLock: bool.fromEnvironment('ALLOW_DISABLE_DRIVE_LOCK', defaultValue: true),
  allowInsecureServer: bool.fromEnvironment('ALLOW_INSECURE_SERVER'),
);

/// Where the display firmware releases are published (`--dart-define=DISPLAY_UPDATE_BASE=...` to change it). The repository has to
/// be public for the app to read it without a token; the app never carries one.
const String displayUpdateBase = String.fromEnvironment('DISPLAY_UPDATE_BASE', defaultValue: 'https://github.com/Romsmo/TN-DSP');

/// The app version shown in the settings (kept in step with pubspec.yaml).
const String appVersion = '0.1.0-beta.2';
