import 'package:flutter/material.dart';
import 'package:tn_core/tn_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_scope.dart';
import '../services/app_config.dart';
import '../services/legal.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'common.dart';

/// "Quellen und Lizenzen": attributions, the legal notice about speed cameras, the library version and the licenses.
class InfoScreen extends StatefulWidget {
  const InfoScreen({super.key});

  @override
  State<InfoScreen> createState() => _InfoScreenState();
}

class _InfoScreenState extends State<InfoScreen> {
  String? _libraryVersion;

  @override
  void initState() {
    super.initState();
    _readVersion();
  }

  Future<void> _readVersion() async {
    final service = context.app.tn.service;
    String? v;
    try {
      v = await service?.libraryVersion();
    } catch (_) {}
    if (mounted) setState(() => _libraryVersion = v);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = context.colors;
    return SubPage(
      title: context.t('info.title'),
      children: [
        Center(
          child: Image.asset(
            dark ? 'assets/images/splash-icon-dark.png' : 'assets/images/splash-icon.png',
            width: 140,
            height: 140,
            semanticLabel: 'Trafficnetwork',
          ),
        ),
        CardSection(children: [
          Body(context.t('info.osm')),
          Body(context.t('info.maplibre')),
          Hint(context.t('info.reports')),
        ]),
        CardSection(title: context.t('info.cameraNotice'), children: [
          noticeText(app.legal.cameraNotice(app.texts.language), TnText.body.copyWith(color: c.text)),
        ]),
        CardSection(children: [
          Hint(context.t('info.library', {'version': _libraryVersion ?? context.t('common.unknown')})),
          Hint(context.t('info.source', {'url': sourceRepoUrl})),
          SoftButton(
            label: sourceRepoUrl,
            onPressed: () => launchUrl(Uri.parse(sourceRepoUrl), mode: LaunchMode.externalApplication),
          ),
        ]),
        CardSection(title: context.t('info.components'), children: [
          Hint(componentList),
          SoftButton(label: context.t('info.components'), onPressed: () => showLicensePage(context: context, applicationName: 'TNViewer', applicationVersion: appVersion)),
        ]),
      ],
    );
  }
}

/// The direct components of the app and their licenses (the full license texts open in the license page).
const String componentList = 'Flutter (BSD-3-Clause)\n'
    'maplibre_gl (BSD-3-Clause), MapLibre Native (BSD-2-Clause)\n'
    'trafficnetwork, trafficnetwork_flutter (Apache-2.0)\n'
    'geolocator (MIT), flutter_secure_storage (BSD-3-Clause)\n'
    'audioplayers (MIT), flutter_tts (MIT), wakelock_plus (BSD-3-Clause)\n'
    'connectivity_plus (BSD-3-Clause), path_provider (BSD-3-Clause)\n'
    'url_launcher (BSD-3-Clause), intl (BSD-3-Clause)';
