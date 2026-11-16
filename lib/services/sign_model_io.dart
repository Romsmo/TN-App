import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:tn_core/tn_core.dart';

const String signModelAsset = 'assets/models/signs.tflite';
const String signLabelsAsset = 'assets/models/signs_labels.json';
const String signDetectorAsset = 'assets/models/signs_detector.tflite';
const String signDetectorMetaAsset = 'assets/models/signs_detector.json';

/// The sign models of the app: the classifier, a small network (see `tool/signs_model/train.py`) that reads a cropped candidate and
/// tells which sign it is, or that it is none; and, when the app has it, the locator (`detect_train.py`), which marks where the signs
/// are in the whole frame. Without the locator the colour-based candidate finder proposes the regions.
class SignModel {
  SignModel._(this.classifier, this.labels, this.locator);

  final SignClassifier classifier;

  /// The catalogue number of each class except the last ("not a sign"); null where the app does not use the class.
  final List<String?> labels;

  /// Null when the app was built without the locator model.
  final SignLocator? locator;

  /// Why the last [load] returned null (for the camera view: a model that is missing and a runtime that does not start are different
  /// problems); null while nothing went wrong.
  static String? lastError;

  /// Why there is no locator although the classifier loaded, or null.
  static String? locatorError;

  /// Loads the models; null when the app was built without the classifier or the runtime could not start it (the sign camera is then
  /// unavailable, nothing else is affected; [lastError] says which). A locator that is missing or fails only disables itself.
  static Future<SignModel?> load() async {
    lastError = null;
    locatorError = null;
    final Map<String, Object?> meta;
    try {
      await rootBundle.load(signModelAsset);
      meta = jsonDecode(await rootBundle.loadString(signLabelsAsset)) as Map<String, Object?>;
    } catch (e) {
      lastError = 'model files: $e';
      return null;
    }
    final classes = meta['classes'];
    final size = meta['size'];
    if (classes is! List || size is! int) {
      lastError = 'model labels: unexpected format';
      return null;
    }
    final labels = [for (final c in classes) c is String ? c : null];
    final TfliteSignClassifier classifier;
    try {
      final interpreter = await Interpreter.fromAsset(signModelAsset);
      classifier = TfliteSignClassifier(interpreter, size, labels.length + 1);
    } catch (e) {
      lastError = 'TensorFlow Lite: $e';
      return null;
    }
    TfliteSignLocator? locator;
    try {
      final dm = jsonDecode(await rootBundle.loadString(signDetectorMetaAsset)) as Map<String, Object?>;
      final inputSize = dm['inputSize'];
      final stride = dm['stride'];
      if (inputSize is! int || stride is! int || inputSize <= 0 || stride <= 0 || inputSize % stride != 0) {
        locatorError = 'locator metadata: unexpected format';
      } else {
        final interpreter = await Interpreter.fromAsset(signDetectorAsset, options: InterpreterOptions()..threads = 2);
        locator = TfliteSignLocator(interpreter, inputSize, stride);
      }
    } catch (e) {
      locatorError = 'locator: $e';
    }
    return SignModel._(classifier, labels, locator);
  }

  void close() {
    (classifier as TfliteSignClassifier).close();
    (locator as TfliteSignLocator?)?.close();
  }
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

/// The locator network through TensorFlow Lite: the picture goes in as raw bytes and the grid comes back as raw bytes, which spares
/// the nested lists a 640 x 640 picture would otherwise be turned into.
class TfliteSignLocator implements SignLocator {
  TfliteSignLocator(this._interpreter, this.inputSize, this.stride);
  final Interpreter _interpreter;

  @override
  final int inputSize;

  @override
  final int stride;

  @override
  Future<Float32List> locate(Float32List rgb) async {
    final input = _interpreter.getInputTensor(0);
    input.data = rgb.buffer.asUint8List(rgb.offsetInBytes, rgb.lengthInBytes);
    _interpreter.invoke();
    final bytes = _interpreter.getOutputTensor(0).data;
    return Float32List.fromList(bytes.buffer.asFloat32List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 4));
  }

  void close() => _interpreter.close();
}
