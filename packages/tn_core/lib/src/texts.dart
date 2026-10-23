/// The app's texts. German for German-language devices, English for everything else. Texts are looked up by key;
/// `{name}` placeholders are filled from the variables.
class Texts {
  Texts({required Map<String, String> de, required Map<String, String> en, String language = 'en'})
      : _tables = {'de': de, 'en': en},
        _language = language == 'de' ? 'de' : 'en';

  final Map<String, Map<String, String>> _tables;
  String _language;

  /// Only `de` or `en`.
  String get language => _language;
  set language(String value) => _language = value == 'de' ? 'de' : 'en';

  static String pickLanguage(String? languageCode) => languageCode == 'de' ? 'de' : 'en';

  /// Whether the (German, authoritative) table knows [key].
  bool has(String key) => _tables['de']!.containsKey(key);

  String t(String key, [Map<String, Object> vars = const {}]) {
    final text = _tables[_language]![key] ?? _tables['de']![key] ?? key;
    return text.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
      final v = vars[m[1]];
      return v == null ? m[0]! : '$v';
    });
  }

  /// The display name of a hazard type. Unknown types (a newer server) show their raw id instead of failing.
  String hazardLabel(String type) {
    final key = 'hazard.$type';
    return has(key) ? t(key) : type;
  }

  /// "1,5 MB" / "1.5 MB": decimal units, one decimal from 1 MB up.
  String formatBytes(num bytes) {
    String number(double value, int digits) {
      final s = value.toStringAsFixed(digits);
      final trimmed = s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
      return _language == 'de' ? trimmed.replaceFirst('.', ',') : trimmed;
    }

    if (bytes < 1000) return '${number(bytes.toDouble(), 0)} B';
    if (bytes < 1000000) return '${number(bytes / 1000, 0)} kB';
    if (bytes < 1000000000) return '${number(bytes / 1000000, 1)} MB';
    return '${number(bytes / 1000000000, 2)} GB';
  }
}
