// The sign classifier runs a neural network through native code (tflite_flutter, dart:ffi); the browser preview has none.
export 'sign_model_web.dart' if (dart.library.io) 'sign_model_io.dart';
