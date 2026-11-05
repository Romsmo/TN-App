import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:tn_core/tn_core.dart';

const String signModelAsset = 'assets/models/signs.tflite';
const String signLabelsAsset = 'assets/models/signs_labels.json';

/// The sign classifier of the app: a small network (see `tool/signs_model`) that reads a cropped candidate and tells which sign it
/// is, or that it is none.
class SignModel {
  SignModel._(this.classifier, this.labels);

  final SignClassifier classifier;

  /// The catalogue number of each class except the last ("not a sign"); null where the app does not use the class.
  final List<String?> labels;

  /// Loads the model; null when the app was built without one (the sign camera is then unavailable, nothing else is affected).
  static Future<SignModel?> load() async {
    final Map<String, Object?> meta;
    try {
      await rootBundle.load(signModelAsset);
      meta = jsonDecode(await rootBundle.loadString(signLabelsAsset)) as Map<String, Object?>;
    } catch (_) {
      return null;
    }
    final classes = meta['classes'];
    final size = meta['size'];
    if (classes is! List || size is! int) return null;
    final labels = [for (final c in classes) c is String ? c : null];
    try {
      final interpreter = await Interpreter.fromAsset(signModelAsset);
      final model = SignModel._(TfliteSignClassifier(interpreter, size, labels.length + 1), labels);
      return model;
    } catch (_) {
      return null;
    }
  }

  void close() => (classifier as TfliteSignClassifier).close();
}

class TfliteSignClassifier implements SignClassifier {
  TfliteSignClassifier(this._interpreter, this.size, this.classCount);
  final Interpreter _interpreter;

  @override
  final int size;

  @override
  final int classCount;

  @override
  Future<List<List<double>>> classify(List<Float32List> crops) async {
    final out = <List<double>>[];
    for (final crop in crops) {
      final input = crop.reshape([1, size, size, 3]);
      final output = [List<double>.filled(classCount, 0)];
      _interpreter.run(input, output);
      out.add(output[0]);
    }
    return out;
  }

  void close() => _interpreter.close();
}
