enum Regime { crawl, city, fast }

enum LocationAccuracy { balanced, high, navigation }

/// How often and how precisely the device is asked for its position.
class Sampling {
  const Sampling(this.regime, this.accuracy, this.distanceIntervalM, this.timeIntervalMs);
  final Regime regime;
  final LocationAccuracy accuracy;
  final int distanceIntervalM;
  final int timeIntervalMs;
}

/// Accuracy and rate only as high as the warnings need: standing or crawling needs little, fast driving needs
/// a fix every second or so because a warning distance is only a few hundred metres.
Sampling samplingFor(double? speedKmh) {
  if (speedKmh == null || speedKmh < 15) return const Sampling(Regime.crawl, LocationAccuracy.balanced, 20, 5000);
  if (speedKmh < 80) return const Sampling(Regime.city, LocationAccuracy.high, 10, 2000);
  return const Sampling(Regime.fast, LocationAccuracy.navigation, 15, 1000);
}

/// The regime to use now, staying in the old one near the boundaries so the location updates are not restarted all the time.
Regime nextRegime(Regime current, double? speedKmh) {
  final wanted = samplingFor(speedKmh).regime;
  if (wanted == current) return current;
  final v = speedKmh ?? 0;
  if (current == Regime.crawl && v < 20) return Regime.crawl;
  if (current == Regime.city && v >= 12 && v < 90 && wanted != Regime.fast) return Regime.city;
  if (current == Regime.city && v >= 70 && v < 80) return Regime.city;
  if (current == Regime.fast && v >= 70) return Regime.fast;
  return wanted;
}

/// Representative speeds used when the updates are restarted at a new regime.
const Map<Regime, double> representativeSpeed = {Regime.crawl: 0, Regime.city: 40, Regime.fast: 100};
