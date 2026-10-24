import 'package:flutter/material.dart';

/// Design tokens, following Apple's design language: grouped backgrounds (#F2F2F7 / true black), white or elevated-grey
/// grouped surfaces, hairline separators, one system blue for actions, status colours only for status. The dark scheme
/// follows the system setting.
@immutable
class TnColors extends ThemeExtension<TnColors> {
  const TnColors({
    required this.text,
    required this.textSecondary,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.tint,
    required this.tintSoft,
    required this.onTint,
    required this.danger,
    required this.warn,
    required this.success,
    required this.overlay,
    required this.brightness,
  });

  final Color text;
  final Color textSecondary;
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color tint;
  final Color tintSoft;
  final Color onTint;
  final Color danger;
  final Color warn;
  final Color success;
  final Color overlay;
  final Brightness brightness;

  static const light = TnColors(
    text: Color(0xFF0A0A0C),
    textSecondary: Color(0xFF6C6C70),
    background: Color(0xFFF2F2F7),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFE9E9EE),
    border: Color(0xFFD1D1D6),
    tint: Color(0xFF0062E0),
    tintSoft: Color(0xFFE3EEFF),
    onTint: Color(0xFFFFFFFF),
    danger: Color(0xFFD70015),
    warn: Color(0xFFB25000),
    success: Color(0xFF1E7B34),
    overlay: Color(0x66000000),
    brightness: Brightness.light,
  );

  static const dark = TnColors(
    text: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFA1A1A6),
    background: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    surfaceAlt: Color(0xFF2C2C2E),
    border: Color(0xFF38383A),
    tint: Color(0xFF4DA3FF),
    tintSoft: Color(0xFF10294A),
    onTint: Color(0xFF001A38),
    danger: Color(0xFFFF6961),
    warn: Color(0xFFFF9F0A),
    success: Color(0xFF30D158),
    overlay: Color(0x99000000),
    brightness: Brightness.dark,
  );

  @override
  TnColors copyWith() => this;

  @override
  TnColors lerp(ThemeExtension<TnColors>? other, double t) => t < 0.5 ? this : (other as TnColors? ?? this);
}

/// The drive mode's own dark, glare-free palette.
class DrivePalette {
  const DrivePalette._();
  static const background = Color(0xFF0B0D10);
  static const surface = Color(0xFF161A1F);
  static const text = Color(0xFFE8EAED);
  static const textSecondary = Color(0xFFA3AAB2);
  static const ok = Color(0xFFE8EAED);
  static const over = Color(0xFFFF7A70);
  static const warnFirst = Color(0xFFE8A93A);
  static const warnSecond = Color(0xFFFF7A70);
  static const tint = Color(0xFF5BB0F0);
  static const onTint = Color(0xFF08141F);
  static const badge = Color(0xFF7A3B35);
  static const tile = Color(0xFF1B2430);
  static const sign = Color(0xFFE9EBEE);
  static const signRing = Color(0xFFD32F2F);
  static const signInk = Color(0xFF0B0D10);
  static const onWarn = Color(0xFF0B0D10);
}

/// Corner radii. Big on purpose: cards 24, sheets 28, pills fully round.
class Radii {
  const Radii._();
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 24;
  static const double sheet = 28;
  static const double pill = 999;
}

class Space {
  const Space._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

/// Room at the bottom of a screen for the floating tab bar.
const double tabBarClearance = 96;

/// The minimum touch target; the drive mode uses bigger ones.
const double minTouch = 52;
const double driveTile = 84;

extension TnTheme on BuildContext {
  TnColors get colors => Theme.of(this).extension<TnColors>()!;
}

/// The type scale: a strong title, a clear section label, readable body, quiet caption.
class TnText {
  const TnText._();
  static const title = TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6);
  static const heading = TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2);
  static const body = TextStyle(fontSize: 16, height: 22 / 16);
  static const label = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8);
  static const caption = TextStyle(fontSize: 13, height: 18 / 13);
}

ThemeData buildTheme(TnColors c) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: c.brightness,
    colorScheme: ColorScheme(
      brightness: c.brightness,
      primary: c.tint,
      onPrimary: c.onTint,
      secondary: c.tint,
      onSecondary: c.onTint,
      error: c.danger,
      onError: c.onTint,
      surface: c.surface,
      onSurface: c.text,
    ),
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    dividerColor: c.border,
    splashFactory: NoSplash.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    extensions: [c],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: c.text, displayColor: c.text),
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TnText.heading.copyWith(color: c.text),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? (c.brightness == Brightness.dark ? const Color(0xFF30D158) : const Color(0xFF34C759)) : c.surfaceAlt,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sheet)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      modalBackgroundColor: c.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceAlt,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.sm), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(color: c.textSecondary),
    ),
  );
}

/// A soft lift for cards, sheets and floating controls.
List<BoxShadow> elevation(BuildContext context, [int level = 1]) {
  final strong = level == 2;
  return [
    BoxShadow(
      color: Colors.black.withValues(alpha: strong ? 0.2 : 0.1),
      blurRadius: strong ? 22 : 12,
      offset: Offset(0, strong ? 10 : 4),
    ),
  ];
}
