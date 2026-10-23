import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tn_core/tn_core.dart';

import 'app.dart';
import 'app_scope.dart';
import 'services/app_config.dart';
import 'services/drive_controller.dart';
import 'services/legal.dart';
import 'services/location.dart';
import 'services/stores.dart';
import 'services/tn_controller.dart';

Future<Map<String, String>> _loadTable(String lang) async =>
    (jsonDecode(await rootBundle.loadString('assets/texts/$lang.json')) as Map).cast<String, String>();

/// Development aid: `--dart-define=SHOW_ERRORS=true` shows the text of a build error where Flutter's release mode would
/// draw a plain grey box.
const bool _showErrors = bool.fromEnvironment('SHOW_ERRORS');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_showErrors) {
    ErrorWidget.builder = (details) => Material(
          color: Colors.yellow,
          child: SingleChildScrollView(child: Text('${details.exceptionAsString()}\n${details.stack}', style: const TextStyle(fontSize: 10, color: Colors.black))),
        );
  }
  await initializeDateFormatting('de');
  await initializeDateFormatting('en');
  final texts = Texts(
    de: await _loadTable('de'),
    en: await _loadTable('en'),
    language: Texts.pickLanguage(ui.PlatformDispatcher.instance.locale.languageCode),
  );
  final legal = await LegalTexts.load();
  final settings = await SettingsStore.open(buildConfig);
  final credentials = await CredentialsStore.open();
  final tn = TnController(settings: settings, credentials: credentials);
  final drive = DriveController(tn: tn, settings: settings, texts: texts);
  final services = AppServices(
    texts: texts,
    legal: legal,
    settings: settings,
    credentials: credentials,
    tn: tn,
    drive: drive,
    position: DevicePosition(),
  );
  runApp(TnApp(services: services));
  // the client starts behind the start screen; the app is usable meanwhile
  await tn.start();
}
