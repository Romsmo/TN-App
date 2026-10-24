import 'dart:convert';
import 'dart:typed_data';

import 'package:tn_display_protocol/tn_display_protocol.dart' as d;

/// The update manifest of a display firmware release (`docs/release-format.md` of the display project, manifest version 1).
class DisplayManifest {
  const DisplayManifest({
    required this.version,
    required this.imageFile,
    required this.imageSize,
    required this.imageSha256,
    required this.minFromVersion,
    required this.protocolVersion,
    required this.minAppProtocol,
    required this.changesDe,
    required this.changesEn,
    required this.signed,
    this.releasedAt,
  });

  /// SemVer of the firmware, the string the display reports in DeviceInfo.
  final String version;
  final String imageFile;
  final int imageSize;

  /// Lower-case hex SHA-256 of the image.
  final String imageSha256;
  final String? minFromVersion;
  final int protocolVersion;
  final int minAppProtocol;
  final List<String> changesDe;
  final List<String> changesEn;

  /// The manifest names a signature. The app cannot verify it yet (no scheme and no key are defined), so this never counts as
  /// verified; it only changes what the screen says.
  final bool signed;
  final String? releasedAt;

  /// Reads a manifest; null when it is not one this app understands (wrong version, missing or malformed fields).
  static DisplayManifest? tryParse(String text) {
    try {
      final j = jsonDecode(text);
      if (j is! Map || j['manifestVersion'] != 1) return null;
      final fw = j['firmware'];
      final proto = j['protocol'];
      if (fw is! Map || proto is! Map) return null;
      final image = fw['image'];
      if (image is! Map) return null;
      final version = fw['version'];
      final file = image['file'];
      final size = image['sizeBytes'];
      final sha = image['sha256'];
      if (version is! String || parseVersion(version) == null) return null;
      if (file is! String || file.isEmpty || file.contains('/') || file.contains('\\') || file.contains('..')) return null;
      if (size is! int || size <= 0) return null;
      if (sha is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha)) return null;
      final pv = proto['version'];
      final minApp = proto['minAppProtocol'];
      if (pv is! int || minApp is! int) return null;
      final changes = j['changes'];
      List<String> list(Object? v) => v is List ? [for (final e in v) if (e is String) e] : const [];
      final minFrom = fw['minFromVersion'];
      return DisplayManifest(
        version: version,
        imageFile: file,
        imageSize: size,
        imageSha256: sha.toLowerCase(),
        minFromVersion: minFrom is String && parseVersion(minFrom) != null ? minFrom : null,
        protocolVersion: pv,
        minAppProtocol: minApp,
        changesDe: changes is Map ? list(changes['de']) : const [],
        changesEn: changes is Map ? list(changes['en']) : const [],
        signed: j['signature'] is Map,
        releasedAt: j['releasedAt'] is String ? j['releasedAt'] as String : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// `1.2.3` or `1.2.3-rc.1` as numbers; null when it is not a version.
List<int>? parseVersion(String v) {
  final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$').firstMatch(v.trim());
  if (m == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
}

/// Negative when [a] is older than [b]; null when one of them is not a version.
int? compareVersions(String a, String b) {
  final x = parseVersion(a);
  final y = parseVersion(b);
  if (x == null || y == null) return null;
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i] < y[i] ? -1 : 1;
  }
  return 0;
}

/// The slot of the display holds 3 MiB.
const int displayImageSlotBytes = 3 * 1024 * 1024;

enum DisplayUpdateVerdict {
  /// A newer firmware that can be installed directly.
  available,
  upToDate,

  /// The installed firmware is older than `minFromVersion`: update in steps (this release cannot be installed directly).
  needsIntermediate,

  /// The release needs a newer app (its protocol is above the app's, or the app is below `minAppProtocol`).
  appTooOld,

  /// The image does not fit the slot, or the display cannot take an update.
  notPossible,
}

DisplayUpdateVerdict judgeUpdate(
  DisplayManifest m, {
  required String installed,
  required bool hasOta,
  int appProtocol = d.protocolVersion,
}) {
  if (!hasOta || m.imageSize > displayImageSlotBytes) return DisplayUpdateVerdict.notPossible;
  if (m.protocolVersion > appProtocol || m.minAppProtocol > appProtocol) return DisplayUpdateVerdict.appTooOld;
  final c = compareVersions(m.version, installed);
  if (c == null) return DisplayUpdateVerdict.notPossible;
  if (c <= 0) return DisplayUpdateVerdict.upToDate;
  final from = m.minFromVersion;
  if (from != null && (compareVersions(installed, from) ?? 0) < 0) return DisplayUpdateVerdict.needsIntermediate;
  return DisplayUpdateVerdict.available;
}

/// Why a downloaded image is refused before the first byte goes to the display.
enum ImageCheck { ok, wrongSize, wrongHash }

ImageCheck checkImage(DisplayManifest m, Uint8List image) {
  if (image.length != m.imageSize || image.length > displayImageSlotBytes) return ImageCheck.wrongSize;
  final hex = d.sha256Of(image).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return hex == m.imageSha256 ? ImageCheck.ok : ImageCheck.wrongHash;
}

enum OtaOutcome { accepted, deviceError, timeout, lostLink, cancelled }

class OtaResult {
  const OtaResult(this.outcome, {this.errorCode});
  final OtaOutcome outcome;

  /// The display's error code (1 no slot, 2 begin, 3 write, 4 SHA-256, 5 finalise) for [OtaOutcome.deviceError].
  final int? errorCode;
  bool get ok => outcome == OtaOutcome.accepted;
}
