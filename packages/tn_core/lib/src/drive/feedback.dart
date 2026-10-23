import 'warning_engine.dart';

/// How the drive mode talks to the driver besides the screen. The device implementation lives in the app; tests use a fake.
abstract interface class Feedback {
  /// A warning: a tone and the sentence, each only when allowed.
  void warn(WarnLevel level, String text, {required bool sound, required bool voice});

  /// Short confirmation after a one-tap report: haptic and a soft tone.
  void confirm({required bool sound});

  /// The "still there?" card appeared.
  void prompt({required bool sound});

  /// Silence everything that is being spoken right now (mute).
  void silence();
}
