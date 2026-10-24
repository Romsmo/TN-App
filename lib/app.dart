import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tn_core/tn_core.dart';

import 'app_scope.dart';
import 'screens/common.dart' show LockGuard;
import 'screens/drive_screen.dart';
import 'screens/join_screens.dart';
import 'screens/map/map_screen.dart';
import 'screens/settings_screen.dart';
import 'services/tn_controller.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

class TnApp extends StatelessWidget {
  const TnApp({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: MaterialApp(
        title: services.texts.t('app.name'),
        debugShowCheckedModeBanner: false,
        theme: buildTheme(TnColors.light),
        darkTheme: buildTheme(TnColors.dark),
        themeMode: ThemeMode.system,
        home: const _StartupGate(child: _Shell()),
        onGenerateRoute: _linkRoute,
        scrollBehavior: const _AppScroll(),
      ),
    );
  }
}

/// A join code opened as a link (`trafficnetwork://join?...`): the platform hands the whole link to the navigator as the route name.
/// The confirmation page opens on top of the app (or, when the app was started by the link, in place of its first page and
/// then continues to the app). A link that is not a valid join code opens the app and shows nothing of it.
MaterialPageRoute<void>? _linkRoute(RouteSettings settings) {
  final name = settings.name;
  if (name == null || !name.toLowerCase().startsWith('$joinScheme://')) return null;
  final r = JoinCode.tryParse(name);
  MaterialPageRoute<void> app() => MaterialPageRoute<void>(builder: (_) => const _StartupGate(child: _Shell()));
  if (r.code == null) return app();
  return MaterialPageRoute<void>(
    settings: const RouteSettings(name: 'join'),
    builder: (context) => JoinConfirmScreen(
      code: r.code!,
      onDone: () => Navigator.of(context).pushReplacement(app()),
    ),
  );
}

/// The start screen: the logo on the system background, over the app, until the first connection attempt is done (at least
/// 900 ms, at most 3 s), then a short fade. It carries no text and asks for nothing; the app is usable behind it.
class _StartupGate extends StatefulWidget {
  const _StartupGate({required this.child});
  final Widget child;

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> with SingleTickerProviderStateMixin {
  static const _min = Duration(milliseconds: 900);
  static const _max = Duration(milliseconds: 3000);
  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 280), value: 1);
  bool _minElapsed = false;
  bool _maxElapsed = false;
  bool _gone = false;
  bool _done = false;
  TnController? _tn;

  @override
  void initState() {
    super.initState();
    Timer(_min, () => _set(() => _minElapsed = true));
    Timer(_max, () => _set(() => _maxElapsed = true));
  }

  void _set(VoidCallback f) {
    if (!mounted) return;
    setState(f);
    _check();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tn = context.app.tn;
    if (!identical(_tn, tn)) {
      _tn?.removeListener(_check);
      _tn = tn..addListener(_check);
    }
  }

  void _check() {
    if (_done || !mounted) return;
    final phase = _tn?.snapshot.phase;
    final ready = phase != null && phase != Phase.starting;
    if (_maxElapsed || (_minElapsed && ready)) {
      _done = true;
      _fade.reverse().whenComplete(() {
        if (mounted) setState(() => _gone = true);
      });
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tn?.removeListener(_check);
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        widget.child,
        if (!_gone)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: _done,
              child: ExcludeSemantics(
                excluding: _done,
                child: FadeTransition(
                  opacity: _fade,
                  child: ColoredBox(
                    color: dark ? Colors.black : Colors.white,
                    child: Center(
                      child: Image.asset(
                        dark ? 'assets/images/splash-icon-dark.png' : 'assets/images/splash-icon.png',
                        width: 200,
                        height: 200,
                        semanticLabel: 'Trafficnetwork',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The three tabs in a floating bar. While a drive runs, the whole shell turns dark and calm.
class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with SingleTickerProviderStateMixin {
  int _index = 0;

  /// A short fade when the tab changes; the tabs themselves stay alive (the map keeps its state).
  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 240), value: 1);

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return ListenableBuilder(
      listenable: app.drive,
      builder: (context, _) {
        final driving = app.drive.snapshot?.active == true;
        final c = context.colors;
        SystemChrome.setSystemUIOverlayStyle(
          (driving || c.brightness == Brightness.dark) ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        );
        return Scaffold(
          backgroundColor: driving && _index == 1 ? DrivePalette.background : c.background,
          extendBody: true,
          body: FadeTransition(
            opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOut),
            child: IndexedStack(
              index: _index,
              children: [
                MapScreen(active: _index == 0),
                const DriveScreen(),
                const LockGuard(child: SettingsScreen()),
              ],
            ),
          ),
          bottomNavigationBar: FloatingTabBar(
            index: _index,
            dark: driving,
            onSelect: (i) {
              if (i == _index) return;
              setState(() => _index = i);
              _fade.forward(from: 0.35);
            },
            items: [
              (label: context.t('tabs.map'), icon: 'map-outline', iconActive: 'map'),
              (label: context.t('tabs.drive'), icon: 'speedometer', iconActive: 'speedometer'),
              (label: context.t('tabs.settings'), icon: 'settings-outline', iconActive: 'settings'),
            ],
          ),
        );
      },
    );
  }
}

/// The rubber-band scrolling of iOS everywhere, without the glow or a visible scroll bar.
class _AppScroll extends MaterialScrollBehavior {
  const _AppScroll();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}
