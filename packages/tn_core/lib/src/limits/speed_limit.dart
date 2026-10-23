import '../drive/lock.dart';
import '../drive/units.dart';
import '../tn/service.dart';
import '../tn/types.dart';

typedef Spot = ({double lat, double lng});

/// The values offered as one tap; anything else is typed. Only a convenience, the library decides what it accepts.
const Map<SpeedUnit, List<int>> quickLimits = {
  SpeedUnit.kmh: [30, 50, 70, 100, 120],
  SpeedUnit.mph: [20, 30, 40, 55, 70],
};

/// The reasons a person can give for "that limit is wrong".
const List<CorrectionReason> wrongReasons = [
  CorrectionReason.wrongValue,
  CorrectionReason.limitLifted,
  CorrectionReason.signMissingOrNew,
  CorrectionReason.other,
];

const Map<SpeedUnit, int> _maxValue = {SpeedUnit.kmh: 200, SpeedUnit.mph: 125};

/// A whole number from 5 up to a plausible maximum; null for everything else (the library still has the last word).
int? parseLimitValue(String text, SpeedUnit unit) {
  final trimmed = text.trim();
  if (!RegExp(r'^\d{1,3}$').hasMatch(trimmed)) return null;
  final value = int.parse(trimmed);
  return value >= 5 && value <= _maxValue[unit]! ? value : null;
}

/// Proposing a limit is a text input and happens while looking at a screen, so it follows the speed lock: not while the
/// drive session's lock is in force, and - with the lock switched on - not while the device itself moves at driving speed
/// (map open without a drive started).
bool entryLocked({required bool lockActive, required bool lockEnabled, required double? deviceSpeedKmh}) {
  if (lockActive) return true;
  return lockEnabled && deviceSpeedKmh != null && deviceSpeedKmh >= lockOnKmh;
}

/// What the card shows for a tapped spot; `error` is a failed lookup (e.g. no connection while outside the offline area).
sealed class LookupState {
  const LookupState();
}

class LookupLoading extends LookupState {
  const LookupLoading();
}

class LookupDone extends LookupState {
  const LookupDone(this.result);
  final SpeedLimitLookup result;
}

class LookupError extends LookupState {
  const LookupError();
}

Future<LookupState> lookupSpot(TnService service, Spot spot) async {
  try {
    return LookupDone(await service.lookupSpeedLimit(spot.lat, spot.lng));
  } catch (_) {
    return const LookupError();
  }
}

enum ProposalProblem {
  roadAlreadyHasLimit,
  invalidValue,
  storageFull,
  network,
  failed,

  /// The stretch of road between two points (`reportSpeedLimitInterval`, `resolveRoadInterval`):
  noRoadFound,
  noRoadBetweenPoints,
  intervalTooLong,
  intervalTooShort,
  noRoadData,

  /// The server does not take speed-limit proposals (an older server, or the feature is switched off).
  notOffered,
}

class ProposalOutcome {
  const ProposalOutcome.ok()
      : ok = true,
        reason = null;
  const ProposalOutcome.fail(ProposalProblem this.reason) : ok = false;
  final bool ok;
  final ProposalProblem? reason;
}

ProposalOutcome _failure(Object error) {
  if (error is TnError) {
    if (error.code == 'roadAlreadyHasLimit') return const ProposalOutcome.fail(ProposalProblem.roadAlreadyHasLimit);
    if (error.code == 'invalidArgument') return const ProposalOutcome.fail(ProposalProblem.invalidValue);
    if (error.code == 'storageFull') return const ProposalOutcome.fail(ProposalProblem.storageFull);
    if (error.code == 'notOffered') return const ProposalOutcome.fail(ProposalProblem.notOffered);
    for (final p in const [
      ProposalProblem.noRoadFound,
      ProposalProblem.noRoadBetweenPoints,
      ProposalProblem.intervalTooLong,
      ProposalProblem.intervalTooShort,
      ProposalProblem.noRoadData,
    ]) {
      if (error.code == p.name) return ProposalOutcome.fail(p);
    }
    if (error.isOffline) return const ProposalOutcome.fail(ProposalProblem.network);
  }
  return const ProposalOutcome.fail(ProposalProblem.failed);
}

/// "No limit on record": proposes a value for the stretch of road between two points the person picked on the map.
/// Stored on the device first and sent with the next sync, like every write.
Future<ProposalOutcome> proposeMissing(TnService service, Spot from, Spot to, int value, SpeedUnit unit) async {
  try {
    await service.reportSpeedLimitInterval(from: from, to: to, value: value, unit: unit);
    return const ProposalOutcome.ok();
  } catch (error) {
    return _failure(error);
  }
}

/// "That limit is wrong": proposes another value for a road that has one.
Future<ProposalOutcome> proposeCorrection(TnService service, Spot spot, int value, SpeedUnit unit, CorrectionReason reason) async {
  try {
    await service.reportWrongSpeedLimit(lat: spot.lat, lng: spot.lng, proposedValue: value, unit: unit, reason: reason);
    return const ProposalOutcome.ok();
  } catch (error) {
    return _failure(error);
  }
}

/// What the preview of a stretch of road says (needs the network).
class IntervalPreview {
  const IntervalPreview({this.road, this.lengthM});
  final String? road;
  final num? lengthM;
}

/// The preview of the stretch between two points, or the problem why it cannot be shown (the person can still send).
Future<({IntervalPreview? preview, ProposalProblem? problem})> previewInterval(TnService service, Spot from, Spot to) async {
  try {
    final r = await service.resolveRoadInterval(from, to);
    final road = r['road'];
    final length = r['lengthM'];
    return (
      preview: IntervalPreview(
        road: road is String ? road : (road is Map && road['name'] is String ? road['name'] as String : null),
        lengthM: length is num ? length : null,
      ),
      problem: null,
    );
  } catch (error) {
    final f = _failure(error);
    return (preview: null, problem: f.reason);
  }
}
