import 'package:flutter/material.dart';
import 'package:tn_core/tn_core.dart';

import 'services/display_controller.dart';
import 'services/drive_controller.dart';
import 'services/legal.dart';
import 'services/location.dart';
import 'services/stores.dart';
import 'services/tn_controller.dart';

/// Everything the screens need, created once in `main`.
class AppServices {
  AppServices({
    required this.texts,
    required this.legal,
    required this.settings,
    required this.credentials,
    required this.tn,
    required this.drive,
    required this.display,
    required this.position,
  });

  final Texts texts;
  final LegalTexts legal;
  final SettingsStore settings;
  final CredentialsStore credentials;
  final TnController tn;
  final DriveController drive;
  final DisplayController display;
  final DevicePosition position;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}

extension AppContext on BuildContext {
  AppServices get app => AppScope.of(this);

  /// A text of the app in the current language.
  String t(String key, [Map<String, Object> vars = const {}]) => app.texts.t(key, vars);
}
