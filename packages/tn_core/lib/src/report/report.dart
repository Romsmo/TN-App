import '../map/camera_types.dart';
import '../texts.dart';
import '../tn/service.dart';
import '../tn/types.dart';

// ---------------------------------------------------------------- duration

/// What the reporter picked in the report sheet: the server's default for the type, or a duration of their own.
sealed class DurationChoice {
  const DurationChoice();
}

class DefaultDuration extends DurationChoice {
  const DefaultDuration();
}

class CustomDuration extends DurationChoice {
  const CustomDuration(this.seconds);
  final int seconds;
}

const defaultChoice = DefaultDuration();

/// Quick choices in the sheet. They are only offers; what is allowed is decided per type by `getReportLimits`.
const List<int> quickSeconds = [15 * 60, 60 * 60, 3 * 3600, 24 * 3600];

enum DurationUnit { min, h, d }

const _unitSeconds = {DurationUnit.min: 60, DurationUnit.h: 3600, DurationUnit.d: 86400};

/// "1,5" + "h" -> 5400. Null for anything that is not a positive, finite number.
int? parseDuration(String amount, DurationUnit unit) {
  final text = amount.trim().replaceFirst(',', '.');
  // JavaScript's Number('') is 0, which is rejected below like every non-positive number
  final value = double.tryParse(text);
  if (value == null || !value.isFinite || value <= 0) return null;
  final seconds = (value * _unitSeconds[unit]! + 0.5).floor();
  return seconds > 0 ? seconds : null;
}

enum DurationProblem { unsupported, tooShort, tooLong }

class DurationCheck {
  const DurationCheck.ok()
      : ok = true,
        reason = null,
        minSeconds = null,
        maxSeconds = null;
  const DurationCheck.fail(DurationProblem this.reason, this.minSeconds, this.maxSeconds) : ok = false;
  final bool ok;
  final DurationProblem? reason;
  final int? minSeconds;
  final int? maxSeconds;
}

/// Is [seconds] inside the bounds the server announced for this type? Unknown bounds (before the first sync) mean: do not guess.
DurationCheck checkDuration(int seconds, ReportLimits limits) {
  final min = limits.minSeconds;
  final max = limits.maxSeconds;
  if (!limits.supported || min == null || max == null) return DurationCheck.fail(DurationProblem.unsupported, min, max);
  if (seconds < min) return DurationCheck.fail(DurationProblem.tooShort, min, max);
  if (seconds > max) return DurationCheck.fail(DurationProblem.tooLong, min, max);
  return const DurationCheck.ok();
}

/// "3 h", "1 d 2 h", "45 min": the two largest non-zero units, rounded to minutes.
String formatDuration(Texts texts, num totalSeconds) {
  final rounded = ((totalSeconds / 60) + 0.5).floor();
  final minutes = rounded < 1 ? 1 : rounded;
  final days = minutes ~/ 1440;
  final hours = (minutes % 1440) ~/ 60;
  final mins = minutes % 60;
  final parts = <String>[
    if (days > 0) texts.t('duration.d', {'n': days}),
    if (hours > 0) texts.t('duration.h', {'n': hours}),
    if (mins > 0 && days == 0) texts.t('duration.min', {'n': mins}),
  ];
  return parts.take(2).join(' ');
}

/// Time left until [expiresAt], from the server's own expiry; null when unknown or already past.
int? remainingSeconds(String? expiresAt, int nowMs) {
  if (expiresAt == null) return null;
  final end = DateTime.tryParse(expiresAt)?.millisecondsSinceEpoch;
  if (end == null) return null;
  final left = ((end - nowMs) / 1000).floor();
  return left > 0 ? left : null;
}

// ---------------------------------------------------------------- catalog

/// The hazard types a user can report. The library offers no list yet (wish), so this is the documented set behind a
/// small interface that a library method can replace.
abstract interface class ReportCatalog {
  List<String> types();
}

class InterimCatalog implements ReportCatalog {
  const InterimCatalog();
  @override
  List<String> types() => const ['traffic', 'accident', 'construction', 'ice', 'breakdown', 'obstacle'];
}

const ReportCatalog interimCatalog = InterimCatalog();

/// What the report sheet on the map offers: the common hazards, plus every camera type, but only where the user has
/// switched cameras on and the country policy allows them in full (never under `zones` or `off`).
List<String> mapReportTypes(bool camerasActive, CameraLevel? maxLevel) =>
    [...interimCatalog.types(), if (camerasActive && maxLevel == CameraLevel.full) ...cameraTypes];

/// The one-tap report buttons of the drive mode: the most common hazards, plus all camera types only where cameras are on
/// and allowed in full.
List<String> driveReportTypes(bool camerasActive, CameraLevel? maxLevel) =>
    ['traffic', 'accident', 'construction', 'ice', if (camerasActive && maxLevel == CameraLevel.full) ...cameraTypes];

// ---------------------------------------------------------------- pending

/// What to tell the user about reports that are stored on the device but not yet sent. Waiting is a normal state of an
/// offline-first app, not an error, so the wording explains instead of alarming.
String? pendingText(Texts texts, {required int pending, required bool waitingForWifi, required bool offline}) {
  if (pending <= 0) return null;
  if (waitingForWifi) return texts.t('pending.wifi', {'count': pending});
  if (offline) return texts.t('pending.offline', {'count': pending});
  return texts.t('pending.sending', {'count': pending});
}

/// A soft notice for writes a server refused for good (rate limit, plausibility, ...). Not shown as a failure.
String? rejectedText(Texts texts, int rejected) => rejected > 0 ? texts.t('rejected.notice', {'count': rejected}) : null;

// ---------------------------------------------------------------- submit

typedef Position = ({double lat, double lng});

enum SubmitProblem { invalidPosition, invalidType, storageFull, failed, ttlUnsupported, ttlOutOfRange }

/// `durationHonoured == false`: the server will use its own duration instead of the requested one.
class SubmitOutcome {
  const SubmitOutcome.ok(this.localId, {this.durationHonoured})
      : ok = true,
        reason = null,
        minSeconds = null,
        maxSeconds = null;
  const SubmitOutcome.fail(SubmitProblem this.reason, {this.minSeconds, this.maxSeconds})
      : ok = false,
        localId = null,
        durationHonoured = null;
  final bool ok;
  final String? localId;
  final bool? durationHonoured;
  final SubmitProblem? reason;
  final int? minSeconds;
  final int? maxSeconds;
}

/// A position the server's plausibility check would accept: finite, in range, not the null island.
bool isPlausiblePosition(Position p) =>
    p.lat.isFinite && p.lng.isFinite && p.lat.abs() <= 90 && p.lng.abs() <= 180 && !(p.lat == 0 && p.lng == 0);

SubmitOutcome _outcomeFromError(Object error) {
  if (error is TnError) {
    if (error.code == 'ttlOutOfRange') return const SubmitOutcome.fail(SubmitProblem.ttlOutOfRange);
    if (error.code == 'invalidArgument') return const SubmitOutcome.fail(SubmitProblem.invalidType);
    if (error.code == 'storageFull') return const SubmitOutcome.fail(SubmitProblem.storageFull);
  }
  return const SubmitOutcome.fail(SubmitProblem.failed);
}

/// Queues a hazard report. It is stored on the device first; nothing leaves the phone until the next sync. Only type
/// and position (and, if the reporter chose one, the duration) are sent. A chosen duration is checked against
/// `getReportLimits` of the type first: unknown limits (before the first sync) or a value outside them queue nothing.
Future<SubmitOutcome> submitHazard(TnService service, String type, Position position,
    [DurationChoice choice = defaultChoice]) async {
  if (!isPlausiblePosition(position)) return const SubmitOutcome.fail(SubmitProblem.invalidPosition);
  try {
    if (choice is DefaultDuration) {
      return SubmitOutcome.ok(await service.submitReport(type, position.lat, position.lng));
    }
    final seconds = (choice as CustomDuration).seconds;
    ReportLimits? limits;
    try {
      limits = await service.getReportLimits(type);
    } catch (_) {
      limits = null;
    }
    if (limits == null) return const SubmitOutcome.fail(SubmitProblem.ttlUnsupported);
    final check = checkDuration(seconds, limits);
    if (!check.ok) {
      return check.reason == DurationProblem.unsupported
          ? const SubmitOutcome.fail(SubmitProblem.ttlUnsupported)
          : SubmitOutcome.fail(SubmitProblem.ttlOutOfRange, minSeconds: check.minSeconds, maxSeconds: check.maxSeconds);
    }
    final submitted = await service.submitReportFor(type, position.lat, position.lng, ttlSeconds: seconds);
    return SubmitOutcome.ok(submitted.localId, durationHonoured: submitted.durationHonoured);
  } catch (error) {
    return _outcomeFromError(error);
  }
}

/// Queues the vote "this permanently installed camera is gone".
Future<SubmitOutcome> reportCameraGone(TnService service, String cameraId) async {
  try {
    return SubmitOutcome.ok(await service.reportCameraRemoved(cameraId));
  } catch (error) {
    return _outcomeFromError(error);
  }
}

/// Queues a vote on someone's report.
Future<SubmitOutcome> voteOnReport(TnService service, String reportId, bool stillThere) async {
  try {
    return SubmitOutcome.ok(await service.confirmReport(reportId, stillThere));
  } catch (error) {
    return _outcomeFromError(error);
  }
}

/// The sentence for a failed report; for a duration outside the server's bounds it names the bounds when they are known.
String submitErrorText(Texts texts, SubmitOutcome failure) {
  final reason = failure.reason!;
  if (reason == SubmitProblem.ttlOutOfRange && failure.minSeconds != null && failure.maxSeconds != null) {
    return texts.t('report.error.ttlRange', {
      'min': formatDuration(texts, failure.minSeconds!),
      'max': formatDuration(texts, failure.maxSeconds!),
    });
  }
  return texts.t('report.error.${reason.name}');
}
