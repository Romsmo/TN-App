import '../tn/service.dart';
import '../tn/types.dart';

/// What the "Offline-Daten" screen shows. A part the library could not answer (no connection) is null, never made up.
class OfflineView {
  const OfflineView({this.settings, this.regions, this.plan, this.usage, this.needsConnection = false});
  final OfflineSettings? settings;

  /// The server's regions; needs a connection.
  final List<OfflineRegion>? regions;
  final StoragePlan? plan;
  final StorageUsage? usage;

  /// The region list or the plan could not be read because the server is not reachable.
  final bool needsConnection;
}

Future<({T? value, bool offline})> _attempt<T>(Future<T> Function() read) async {
  try {
    return (value: await read(), offline: false);
  } catch (error) {
    // `network` is the library's honest "no server"; other errors are not a connection matter, but the screen has nothing to show either.
    return (value: null, offline: error is TnError && error.isOffline);
  }
}

/// Reads settings and usage (local) and the region list and plan (they ask the server).
Future<OfflineView> loadOfflineView(TnService service) async {
  final settings = _attempt(service.getOfflineSettings);
  final usage = _attempt(service.getStorageUsage);
  final regions = _attempt(service.listOfflineRegions);
  final plan = _attempt(service.getStoragePlan);
  final results = await (settings, usage, regions, plan).wait;
  return OfflineView(
    settings: results.$1.value,
    usage: results.$2.value,
    regions: results.$3.value,
    plan: results.$4.value,
    needsConnection: results.$3.offline || results.$4.offline,
  );
}

/// The region ids after switching one: chosen regions stay in the order they were chosen.
List<String> toggleRegion(List<String> selected, String id) =>
    selected.contains(id) ? [for (final r in selected) if (r != id) r] : [...selected, id];

/// A name for a region: the country's own name in the app language where the server says which country, otherwise the id.
/// [countryName] resolves an ISO code to a name (the app supplies it from the platform's locale data).
String regionName(OfflineRegion region, String language, String? Function(String country, String language) countryName) {
  final country = region.country;
  if (country != null) {
    final name = countryName(country, language);
    if (name != null && name.isNotEmpty) return name;
  }
  return region.id;
}

/// Sizes the user can cap the offline data at (bytes); null = no limit.
const List<int?> limitChoices = [null, 500000000, 1000000000, 2000000000];

/// Bytes the device really holds right now: the store's own size where known, else the library's estimate.
int usedBytes(StorageUsage usage) => usage.storeBytes ?? usage.estimatedDeviceBytes;

/// Whether a deselected region is still on the device and goes with the next sync.
bool isLeaving(OfflineRegion region, OfflineSettings settings) =>
    settings.mode == OfflineMode.regions && !settings.regions.contains(region.id) && region.storedTiles > 0;

/// Country names for the ISO codes the app is likely to see (de/en). Anything else falls back to the region id.
const Map<String, (String, String)> _countryNames = {
  'DE': ('Deutschland', 'Germany'),
  'AT': ('Österreich', 'Austria'),
  'CH': ('Schweiz', 'Switzerland'),
  'FR': ('Frankreich', 'France'),
  'IT': ('Italien', 'Italy'),
  'NL': ('Niederlande', 'Netherlands'),
  'BE': ('Belgien', 'Belgium'),
  'LU': ('Luxemburg', 'Luxembourg'),
  'PL': ('Polen', 'Poland'),
  'CZ': ('Tschechien', 'Czechia'),
  'DK': ('Dänemark', 'Denmark'),
  'ES': ('Spanien', 'Spain'),
  'PT': ('Portugal', 'Portugal'),
  'GB': ('Vereinigtes Königreich', 'United Kingdom'),
  'IE': ('Irland', 'Ireland'),
  'SE': ('Schweden', 'Sweden'),
  'NO': ('Norwegen', 'Norway'),
  'FI': ('Finnland', 'Finland'),
  'HU': ('Ungarn', 'Hungary'),
  'SK': ('Slowakei', 'Slovakia'),
  'SI': ('Slowenien', 'Slovenia'),
  'HR': ('Kroatien', 'Croatia'),
  'US': ('Vereinigte Staaten', 'United States'),
};

/// A built-in country-name lookup for [regionName].
String? builtInCountryName(String country, String language) {
  final names = _countryNames[country.toUpperCase()];
  if (names == null) return null;
  return language == 'de' ? names.$1 : names.$2;
}
