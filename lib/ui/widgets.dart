import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoSlidingSegmentedControl;
import 'package:flutter/material.dart';

import '../app_scope.dart';
import 'icons.dart';
import 'theme.dart';

/// A large screen title.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Text(text, style: TnText.title.copyWith(color: context.colors.text)),
      );
}

/// A section label: small, bold, spaced.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.sm),
        child: Semantics(
          header: true,
          child: Text(text.toUpperCase(), style: TnText.label.copyWith(color: context.colors.textSecondary)),
        ),
      );
}

/// A rounded group of rows with hairline separators, like the iOS settings.
class Group extends StatelessWidget {
  const Group({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.lg)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 0.5, thickness: 0.5, indent: Space.lg, color: c.border),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A coloured square with a symbol, 30 pt, radius 8.
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.color});
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: color ?? context.colors.tint, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 18, color: Colors.white),
      );
}

/// One row of a [Group]: title, optional hint and a trailing widget; a tap area of at least 52 pt.
class Row3 extends StatelessWidget {
  const Row3({super.key, required this.title, this.hint, this.leading, this.trailing, this.onTap, this.danger = false, this.semanticsLabel});
  final String title;
  final String? hint;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minTouch),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: Space.md)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: TnText.body.copyWith(color: danger ? c.danger : c.text)),
                  if (hint != null) Text(hint!, style: TnText.caption.copyWith(color: c.textSecondary)),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: Space.sm), trailing!],
          ],
        ),
      ),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// A switch row with the title as its accessibility label.
class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.title, required this.value, required this.onChanged, this.hint, this.leading, this.enabled = true});
  final String title;
  final String? hint;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? leading;
  final bool enabled;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Row3(
          title: title,
          hint: hint,
          leading: leading,
          trailing: Switch(value: value, onChanged: enabled ? onChanged : null),
          onTap: enabled && onChanged != null ? () => onChanged!(!value) : null,
        ),
      );
}

/// A filled action button, at least 52 pt high.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.icon, this.danger = false, this.expand = true});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool danger;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = danger ? c.danger : c.tint;
    return SizedBox(
      width: expand ? double.infinity : null,
      height: minTouch,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: danger ? Colors.white : c.onTint,
          disabledBackgroundColor: c.surfaceAlt,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: Space.sm)],
            Flexible(child: Text(label, textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }
}

/// A quiet button with a tinted soft background.
class SoftButton extends StatelessWidget {
  const SoftButton({super.key, required this.label, required this.onPressed, this.icon, this.expand = true, this.danger = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = danger ? c.danger : c.tint;
    return SizedBox(
      width: expand ? double.infinity : null,
      height: minTouch,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: danger ? c.danger.withValues(alpha: 0.12) : c.tintSoft,
          foregroundColor: fg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: Space.sm)],
            Flexible(child: Text(label, textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }
}

/// A round floating button (52 pt) with a symbol.
class RoundButton extends StatelessWidget {
  const RoundButton({super.key, required this.icon, required this.label, required this.onPressed, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      selected: active,
      child: Tooltip(
        message: label,
        child: Material(
          color: active ? c.tint : c.surface,
          elevation: 3,
          shadowColor: Colors.black45,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(width: minTouch, height: minTouch, child: Icon(icon, color: active ? c.onTint : c.text)),
          ),
        ),
      ),
    );
  }
}

/// A pill chip that can be on or off.
class FilterPill extends StatelessWidget {
  const FilterPill({super.key, required this.label, required this.color, required this.icon, required this.on, required this.onTap});
  final String label;
  final Color color;
  final IconData icon;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      toggled: on,
      label: label,
      child: Material(
        color: on ? c.surface : c.surfaceAlt,
        elevation: on ? 2 : 0,
        shadowColor: Colors.black38,
        borderRadius: BorderRadius.circular(Radii.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.pill),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(on ? icon : Icons.visibility_off_outlined, size: 16, color: on ? color : c.textSecondary),
                  const SizedBox(width: 6),
                  Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? c.text : c.textSecondary)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact notice with a symbol; [alert] announces it to screen readers.
class Notice extends StatelessWidget {
  const Notice({super.key, required this.text, this.icon = Icons.info_outline, this.color, this.action, this.actionLabel});
  final String text;
  final IconData icon;
  final Color? color;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        decoration: BoxDecoration(
          color: c.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(Radii.md),
          boxShadow: elevation(context),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 18, color: color ?? c.textSecondary)),
            const SizedBox(width: Space.sm),
            Expanded(child: Text(text, style: TnText.caption.copyWith(color: c.text))),
            if (action != null && actionLabel != null)
              Padding(
                padding: const EdgeInsets.only(left: Space.sm),
                child: GestureDetector(
                  onTap: action,
                  child: Text(actionLabel!, style: TnText.caption.copyWith(color: c.tint, fontWeight: FontWeight.w700)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A segmented switch (iOS style).
class Segments<T extends Object> extends StatelessWidget {
  const Segments({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CupertinoSlidingSegmentedControl<T>(
      groupValue: value,
      backgroundColor: c.surfaceAlt,
      thumbColor: c.surface,
      children: {
        for (final e in options.entries)
          e.key: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(e.value, style: TextStyle(color: c.text, fontWeight: FontWeight.w600)),
          ),
      },
      onValueChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

/// A confirmation dialog; resolves true when confirmed.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
  bool danger = false,
  Widget? messageWidget,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final c = ctx.colors;
      return AlertDialog(
        title: Text(title, style: TnText.heading.copyWith(color: c.text)),
        content: SingleChildScrollView(child: messageWidget ?? Text(message, style: TnText.body.copyWith(color: c.text))),
        actionsPadding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          PrimaryButton(label: confirmLabel, danger: danger, onPressed: () => Navigator.of(ctx).pop(true)),
          const SizedBox(height: Space.sm),
          SoftButton(label: cancelLabel ?? ctx.t('common.cancel'), onPressed: () => Navigator.of(ctx).pop(false)),
        ],
      );
    },
  );
  return result == true;
}

/// A notice with a single acknowledge button.
Future<void> infoDialog(BuildContext context, {required String title, required Widget body, required String okLabel}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final c = ctx.colors;
      return AlertDialog(
        title: Text(title, style: TnText.heading.copyWith(color: c.text)),
        content: SingleChildScrollView(child: body),
        actionsPadding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
        actions: [PrimaryButton(label: okLabel, onPressed: () => Navigator.of(ctx).pop())],
      );
    },
  );
}

/// Shows a modal sheet from below with a grabber.
Future<T?> showSheet<T>(BuildContext context, WidgetBuilder builder, {bool scrollControlled = true}) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: scrollControlled,
      useSafeArea: true,
      showDragHandle: false,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: Space.sm),
            Container(width: 40, height: 5, decoration: BoxDecoration(color: ctx.colors.border, borderRadius: BorderRadius.circular(3))),
            Flexible(child: builder(ctx)),
          ],
        ),
      ),
    );

/// The floating pill tab bar; blurred on iOS-like surfaces.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({super.key, required this.index, required this.onSelect, required this.items, this.dark = false});
  final int index;
  final ValueChanged<int> onSelect;
  final List<({String label, String icon, String iconActive})> items;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = dark ? const Color(0xFF1B2430) : c.surface.withValues(alpha: 0.82);
    final active = dark ? const Color(0xFF5BB0F0) : c.tint;
    final idle = dark ? const Color(0xFFA3AAB2) : c.textSecondary;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, 14 + MediaQuery.paddingOf(context).bottom * 0.5),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.pill),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 66,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(Radii.pill),
              border: Border.all(color: c.border.withValues(alpha: 0.6), width: 0.5),
            ),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == index,
                      label: items[i].label,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(Radii.pill),
                        onTap: () => onSelect(i),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(iconFor(i == index ? items[i].iconActive : items[i].icon), size: 24, color: i == index ? active : idle),
                            const SizedBox(height: 2),
                            Text(items[i].label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: i == index ? active : idle)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
