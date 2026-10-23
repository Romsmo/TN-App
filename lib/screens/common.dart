import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tn_core/tn_core.dart';

import '../app_scope.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Shows its content only when the speed lock is not in force; otherwise a short explanation instead.
class LockGuard extends StatelessWidget {
  const LockGuard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return ListenableBuilder(
      listenable: Listenable.merge([app.drive, app.settings]),
      builder: (context, _) {
        if (!app.drive.lockActive) return child;
        final c = context.colors;
        return ColoredBox(
          color: c.background,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, tabBarClearance + 16),
              child: Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock, size: 36, color: c.tint),
                    const SizedBox(height: Space.md),
                    ScreenTitle(context.t('lock.title')),
                    const SizedBox(height: Space.md),
                    Text(context.t('lock.body'), style: TnText.body.copyWith(color: c.textSecondary)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The emergency mode as the user sees it: what is missing, what still works, and the two things they can do about it.
/// It is a card on the map, not a dead end: the map, reporting and the drive mode stay usable.
class EmergencyCard extends StatefulWidget {
  const EmergencyCard({super.key, required this.reason, required this.onRetry, required this.onSetup});
  final Emergency reason;
  final Future<void> Function() onRetry;
  final VoidCallback onSetup;

  @override
  State<EmergencyCard> createState() => _EmergencyCardState();
}

class _EmergencyCardState extends State<EmergencyCard> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: Space.lg),
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.lg), boxShadow: elevation(context, 2)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: c.warn, borderRadius: BorderRadius.circular(9)),
                child: const Icon(Icons.cloud_off, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Semantics(header: true, child: Text(context.t('emergency.title'), style: TnText.heading.copyWith(color: c.text))),
            ]),
            const SizedBox(height: Space.sm),
            Text(context.t(widget.reason == Emergency.noAccess ? 'emergency.noAccess' : 'emergency.noServer'),
                style: TnText.caption.copyWith(color: c.textSecondary)),
            const SizedBox(height: Space.sm),
            Text(context.t('emergency.auto'), style: TnText.caption.copyWith(color: c.textSecondary)),
            const SizedBox(height: Space.md),
            PrimaryButton(icon: Icons.refresh, label: _busy ? context.t('emergency.retrying') : context.t('emergency.retry'), onPressed: _busy ? null : _retry),
            const SizedBox(height: Space.sm),
            SoftButton(icon: Icons.dns, label: context.t('emergency.setup'), onPressed: widget.onSetup),
          ],
        ),
      ),
    );
  }
}

/// A date and time in the app language.
String formatDateTime(BuildContext context, int unixMs) {
  final lang = context.app.texts.language;
  return DateFormat.yMd(lang).add_jm().format(DateTime.fromMillisecondsSinceEpoch(unixMs));
}

/// A page with an app bar and a scrolling body, used by the sub pages of the settings.
class SubPage extends StatelessWidget {
  const SubPage({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, tabBarClearance + 16),
            children: children,
          ),
        ),
      );
}

/// A section with a title and a card holding its content.
class CardSection extends StatelessWidget {
  const CardSection({super.key, this.title, required this.children});
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) Padding(padding: const EdgeInsets.only(top: Space.lg, bottom: Space.sm, left: 4), child: Semantics(header: true, child: Text(title!.toUpperCase(), style: TnText.label.copyWith(color: c.textSecondary)))),
        if (title == null) const SizedBox(height: Space.lg),
        Container(
          padding: const EdgeInsets.all(Space.lg),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.lg)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: Space.md), children[i]],
            ],
          ),
        ),
      ],
    );
  }
}

/// Quiet explanatory text.
class Hint extends StatelessWidget {
  const Hint(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: TnText.caption.copyWith(color: context.colors.textSecondary));
}

/// Regular body text.
class Body extends StatelessWidget {
  const Body(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: TnText.body.copyWith(color: context.colors.text));
}
