import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tn_core/tn_core.dart';

void main() {
  test('the classifier reads exactly the speed limits the app knows (a new model and the code must agree)', () {
    final labels = (jsonDecode(File('assets/models/signs_labels.json').readAsStringSync()) as Map)['classes'] as List;
    final limits = [for (final l in labels) if (l is String && l.startsWith(speedVzPrefix)) speedOfVz(l)];
    expect(limits, everyElement(isNotNull), reason: 'a limit label the code does not know');
    expect(limits.cast<int>().toSet(), readableSpeeds.toSet());
  });
}
