import 'package:tn_core/tn_core.dart';

/// The browser preview has no neural network runtime (it needs native code): there is no sign model there.
class SignModel {
  SignModel._();

  SignClassifier get classifier => throw UnsupportedError('no sign model in the browser preview');
  List<String?> get labels => const [];

  static Future<SignModel?> load() async => null;

  void close() {}
}
