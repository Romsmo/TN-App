import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

/// A piece of the legal notice; [strong] is shown in bold.
class Segment {
  const Segment(this.text, {this.strong = false});
  final String text;
  final bool strong;
}

/// The legal wordings that the operator prescribed, word for word (`assets/texts/legal.json`, copied from the export).
/// German is binding; the English versions are an unapproved translation.
class LegalTexts {
  LegalTexts._(this.cameraNoticeVersion, this._camera, this._driveExtra, this._lockWarning);

  static Future<LegalTexts> load() async {
    final j = jsonDecode(await rootBundle.loadString('assets/texts/legal.json')) as Map<String, dynamic>;
    final camera = (j['CAMERA_NOTICE'] as Map).map(
      (lang, segs) => MapEntry(lang as String, [
        for (final s in segs as List) Segment(s['text'] as String, strong: s['strong'] == true),
      ]),
    );
    return LegalTexts._(
      j['CAMERA_NOTICE_VERSION'] as String,
      camera,
      (j['DRIVE_NOTICE_EXTRA'] as Map).cast<String, String>(),
      (j['LOCK_WARNING'] as Map).cast<String, String>(),
    );
  }

  /// Version of our wording; the notice is shown again when it changes.
  final String cameraNoticeVersion;
  final Map<String, List<Segment>> _camera;
  final Map<String, String> _driveExtra;
  final Map<String, String> _lockWarning;

  List<Segment> cameraNotice(String language) => _camera[language] ?? _camera['en']!;

  /// The notice at the first start of the drive mode: the camera notice plus the hint to operate the app only as a
  /// passenger or when stationary.
  List<Segment> driveNotice(String language) =>
      [...cameraNotice(language), Segment('\n\n${_driveExtra[language] ?? _driveExtra['en']}')];

  String lockWarning(String language) => _lockWarning[language] ?? _lockWarning['en']!;
}

/// The segments as rich text.
Widget noticeText(List<Segment> segments, TextStyle style) => Text.rich(
      TextSpan(
        children: [
          for (final s in segments)
            TextSpan(text: s.text, style: s.strong ? style.copyWith(fontWeight: FontWeight.w800) : style),
        ],
      ),
    );
