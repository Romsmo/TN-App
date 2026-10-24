/// The app-side rules for building `leftSigns` / `rightSigns`: which column a sign
/// belongs in, which signs replace each other, and the "newest 3" cap. The display
/// renders the two lists exactly as sent; it applies none of this. The data comes from
/// docs/contract/sign-rules.json (via sign_rules_data.dart); the test vectors in
/// docs/contract/vectors/sign-rules.json pin the behaviour.
library;

import 'constants.dart';
import 'sign_rules_data.dart';

export 'sign_rules_data.dart'
    show SignInfo, vendoredSigns, signFamilies, signCancels, signRulesDisplayedPerColumn;

/// Wire code of a VzNr: `major * 100 + minor` ('142-10' → 14210, '276' → 27600).
int signCodeOf(String vzNr) {
  final i = vzNr.indexOf('-');
  final major = int.parse(i < 0 ? vzNr : vzNr.substring(0, i));
  final minor = i < 0 ? 0 : int.parse(vzNr.substring(i + 1));
  return major * 100 + minor;
}

int signMajorOf(String vzNr) => signCodeOf(vzNr) ~/ 100;

/// The two sign columns, as VzNr strings, oldest first.
class SignLists {
  const SignLists(this.left, this.right);
  const SignLists.empty()
      : left = const [],
        right = const [];

  final List<String> left;
  final List<String> right;

  /// The codes to put on the wire.
  List<int> get leftCodes => left.map(signCodeOf).toList();
  List<int> get rightCodes => right.map(signCodeOf).toList();
}

class SignAddResult {
  const SignAddResult(this.lists, this.removed);
  final SignLists lists;

  /// Signs that were evicted (replaced, cancelled, or pushed out as the oldest).
  final List<String> removed;
}

final Map<String, String> _familyOf = {
  for (final e in signFamilies.entries)
    for (final vz in e.value) vz: e.key,
};

/// `2xx` (Vorschrift- and Verbotszeichen) go left, everything else (Gefahrzeichen) right.
bool signGoesLeft(String vzNr) {
  final major = signMajorOf(vzNr);
  return major >= 200 && major < 300;
}

/// True if adding [newVz] must evict [other].
bool signConflicts(String newVz, String other) {
  final fam = _familyOf[newVz];
  if (fam != null && _familyOf[other] == fam) return true;
  if (signMajorOf(newVz) == signMajorOf(other)) return true;
  final cancelled = signCancels[newVz];
  return cancelled != null && cancelled.contains(other.split('-').first);
}

/// Adds [vzNr]: evicts every conflicting sign from BOTH columns, appends it to its own
/// column, and drops the oldest entries beyond the displayed count.
SignAddResult addSign(SignLists current, String vzNr) {
  final removed = <String>[];
  List<String> keep(List<String> col) {
    final out = <String>[];
    for (final s in col) {
      if (signConflicts(vzNr, s)) {
        removed.add(s);
      } else {
        out.add(s);
      }
    }
    return out;
  }

  final left = keep(current.left);
  final right = keep(current.right);
  final target = signGoesLeft(vzNr) ? left : right;
  target.add(vzNr);
  while (target.length > signsDisplayed) {
    removed.add(target.removeAt(0));
  }
  return SignAddResult(SignLists(left, right), removed);
}

/// Removes [vzNr] from whichever column holds it; nothing else changes.
SignLists removeSign(SignLists current, String vzNr) => SignLists(
      current.left.where((s) => s != vzNr).toList(),
      current.right.where((s) => s != vzNr).toList(),
    );
