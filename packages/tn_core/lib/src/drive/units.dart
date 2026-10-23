import 'geo.dart';

enum SpeedUnit {
  kmh,
  mph;

  static SpeedUnit parse(Object? value) => value == 'mph' ? SpeedUnit.mph : SpeedUnit.kmh;
  String get wire => name;
}

const double kmhPerMph = 1.609344;

double toKmh(num value, SpeedUnit unit) => unit == SpeedUnit.kmh ? value.toDouble() : value * kmhPerMph;

double fromKmh(num kmh, SpeedUnit unit) => unit == SpeedUnit.kmh ? kmh.toDouble() : kmh / kmhPerMph;

/// Speed in the user's unit as a whole number.
int? displaySpeed(double? kmh, SpeedUnit unit) =>
    kmh == null ? null : jsRound(fromKmh(kmh < 0 ? 0 : kmh, unit));

/// A limit as the library stores it (never converted there), shown in the user's unit; mph limits are 5-steps.
int displayLimit(num value, SpeedUnit from, SpeedUnit to) {
  if (from == to) return jsRound(value);
  final converted = fromKmh(toKmh(value, from), to);
  return jsRound(converted / 5) * 5;
}

enum SpeedState { ok, over }

/// Over the limit by more than [toleranceKmh] (default 3 km/h of GPS and speedometer slack).
SpeedState speedState(double? speedKmh, ({num value, SpeedUnit unit})? limit, {double toleranceKmh = 3}) {
  if (speedKmh == null || limit == null) return SpeedState.ok;
  return speedKmh > toKmh(limit.value, limit.unit) + toleranceKmh ? SpeedState.over : SpeedState.ok;
}

String unitLabel(SpeedUnit unit) => unit == SpeedUnit.kmh ? 'km/h' : 'mph';
