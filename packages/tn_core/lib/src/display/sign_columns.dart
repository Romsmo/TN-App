import 'package:tn_display_protocol/tn_display_protocol.dart' as d;

import '../tn/types.dart';

/// A sign that begins less than this far ahead is already shown: it is the distance at which the sign itself stands in sight.
const double signsShownAheadM = 100;

/// The two columns of the display, as wire codes (oldest first).
class SignColumns {
  const SignColumns(this.left, this.right);
  const SignColumns.empty()
      : left = const [],
        right = const [];

  final List<int> left;
  final List<int> right;

  bool get isEmpty => left.isEmpty && right.isEmpty;

  @override
  bool operator ==(Object other) => other is SignColumns && _same(left, other.left) && _same(right, other.right);

  @override
  int get hashCode => Object.hash(Object.hashAll(left), Object.hashAll(right));

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

final Map<String, d.SignInfo> _catalogue = {for (final s in d.vendoredSigns) s.vzNr: s};

/// The catalogue number of a library sign type (`DE:142-10` -> `142-10`), or null for another country's sign and for one the display
/// cannot draw: those are never passed on.
String? vzNrOf(String signType) {
  if (!signType.startsWith('DE:')) return null;
  final vz = signType.substring(3);
  return _catalogue.containsKey(vz) ? vz : null;
}

/// The official German name of a library sign type, or null where the display does not know it.
String? signNameOf(String signType) {
  final vz = vzNrOf(signType);
  return vz == null ? null : _catalogue[vz]!.labelDe;
}

/// Builds the display's sign columns from what applies at the position.
///
/// Only signs that apply now (or begin within [signsShownAheadM]) and that enough devices have confirmed; an unconfirmed entry is never
/// shown (better one sign too few than an invented one). The ones that began longest ago come first, so a sign that begins later is
/// the newer one and wins where two replace each other (276 then 280, 283 then 286), and the display's cap of three keeps the newest.
/// Side, replacement and cap are the display contract's (`sign-rules.json`); the library hands out raw entries.
SignColumns signColumnsFor(Iterable<ContextSign> signs) {
  final shown = [
    for (final s in signs)
      if (s.activeNow && s.confirmed && s.startsInM <= signsShownAheadM && vzNrOf(s.signType) != null) s,
  ]..sort((a, b) {
      final c = a.startsInM.compareTo(b.startsInM);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  var lists = const d.SignLists.empty();
  for (final s in shown) {
    lists = d.addSign(lists, vzNrOf(s.signType)!).lists;
  }
  return SignColumns(lists.leftCodes, lists.rightCodes);
}
