import 'package:flutter/material.dart';
import 'package:tn_core/tn_core.dart';

import '../../app_scope.dart';
import '../../ui/icons.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../drive_screen.dart' show hazardColorOf;

/// Where a report would go: the device's position, or a spot marked on the map. Null while there is none.
typedef ReportLocation = ({double lat, double lng, bool fromMap})?;

/// A chip that can be selected.
class ChoiceChip2 extends StatelessWidget {
  const ChoiceChip2({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: minTouch - 4),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: selected ? c.tint : c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.md)),
          child: Center(
            widthFactor: 1,
            child: Text(label, style: TnText.caption.copyWith(color: selected ? c.onTint : c.text, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

/// "How long should the report apply?": the server's default for the type, or a duration of their own.
class DurationPicker extends StatefulWidget {
  const DurationPicker({super.key, required this.choice, required this.onChoice});
  final DurationChoice choice;
  final ValueChanged<DurationChoice> onChoice;

  @override
  State<DurationPicker> createState() => _DurationPickerState();
}

class _DurationPickerState extends State<DurationPicker> {
  final _amount = TextEditingController();
  DurationUnit _unit = DurationUnit.h;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _typed(String text, DurationUnit unit) {
    setState(() => _unit = unit);
    if (text.trim().isEmpty) {
      widget.onChoice(const CustomDuration(0)); // custom, but not a valid number yet: the tiles stay locked
      return;
    }
    final seconds = parseDuration(text, unit);
    widget.onChoice(CustomDuration(seconds ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final texts = context.app.texts;
    final custom = widget.choice is CustomDuration;
    final seconds = custom ? (widget.choice as CustomDuration).seconds : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(context.t('report.duration'), style: TnText.caption.copyWith(color: c.text, fontWeight: FontWeight.w700))),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip2(label: context.t('report.duration.default'), selected: !custom, onTap: () => widget.onChoice(defaultChoice)),
          ChoiceChip2(
            label: context.t('report.duration.custom'),
            selected: custom,
            onTap: () => widget.onChoice(const CustomDuration(0)),
          ),
        ]),
        if (custom) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in quickSeconds)
              ChoiceChip2(
                label: formatDuration(texts, s),
                selected: seconds == s,
                onTap: () {
                  _amount.clear();
                  widget.onChoice(CustomDuration(s));
                },
              ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(
              width: 110,
              child: TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(hintText: context.t('report.duration.input')),
                onChanged: (t) => _typed(t, _unit),
              ),
            ),
            const SizedBox(width: 8),
            for (final u in DurationUnit.values) ...[
              ChoiceChip2(label: context.t('report.duration.unit.${u.name}'), selected: _unit == u, onTap: () => _typed(_amount.text, u)),
              const SizedBox(width: 8),
            ],
          ]),
          const SizedBox(height: 6),
          Text(context.t('report.duration.hint'), style: TnText.caption.copyWith(color: c.textSecondary)),
        ],
      ],
    );
  }
}

/// The "report" bottom sheet over the map: where, how long, and one big tile per type.
class ReportSheet extends StatefulWidget {
  const ReportSheet({
    super.key,
    required this.types,
    required this.location,
    required this.locating,
    required this.message,
    required this.onPick,
    required this.onCancel,
  });

  final List<String> types;
  final ReportLocation location;
  final bool locating;
  final String? message;
  final void Function(String type, DurationChoice choice) onPick;
  final VoidCallback onCancel;

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  DurationChoice _choice = defaultChoice;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final loc = widget.location;
    final invalidCustom = _choice is CustomDuration && (_choice as CustomDuration).seconds <= 0;
    final enabled = loc != null && !invalidCustom;
    final plain = widget.types.where((t) => !isCameraType(t)).toList();
    final cameras = widget.types.where(isCameraType).toList();
    final where = loc != null
        ? (loc.fromMap ? context.t('report.atMap') : context.t('report.atDevice'))
        : widget.locating
            ? context.t('report.locating')
            : context.t('report.noLocation');
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.sheet), boxShadow: elevation(context, 2)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: 8),
            Semantics(header: true, child: Text(context.t('report.title'), style: TnText.heading.copyWith(color: c.text))),
            const SizedBox(height: 8),
            Row(children: [
              Icon(loc?.fromMap == true ? Icons.place : Icons.my_location, size: 16, color: c.tint),
              const SizedBox(width: 6),
              Expanded(child: Text(where, style: TnText.caption.copyWith(color: c.textSecondary))),
            ]),
            const SizedBox(height: 4),
            Text(context.t('report.hint'), style: TnText.caption.copyWith(color: c.textSecondary)),
            const SizedBox(height: 8),
            DurationPicker(choice: _choice, onChoice: (v) => setState(() => _choice = v)),
            const SizedBox(height: 8),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _Grid(types: plain, enabled: enabled, onPick: (t) => widget.onPick(t, _choice)),
                    if (cameras.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Semantics(header: true, child: Text(context.t('hazard.cameras').toUpperCase(), style: TnText.label.copyWith(color: c.textSecondary))),
                      const SizedBox(height: 6),
                      _Grid(types: cameras, enabled: enabled, onPick: (t) => widget.onPick(t, _choice)),
                    ],
                  ]),
                ),
              ),
            ),
            if (widget.message != null) ...[
              const SizedBox(height: 8),
              Semantics(liveRegion: true, child: Text(widget.message!, style: TnText.body.copyWith(color: c.text))),
            ],
            const SizedBox(height: 8),
            SoftButton(label: context.t('report.cancel'), onPressed: widget.onCancel),
          ],
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.types, required this.enabled, required this.onPick});
  final List<String> types;
  final bool enabled;
  final void Function(String type) onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final texts = context.app.texts;
    return LayoutBuilder(builder: (context, box) {
      final w = (box.maxWidth - 20) / 3;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        for (final type in types)
          Semantics(
            button: true,
            enabled: enabled,
            label: context.t('report.type', {'type': texts.hazardLabel(type)}),
            child: Opacity(
              opacity: enabled ? 1 : 0.4,
              child: GestureDetector(
                onTap: enabled ? () => onPick(type) : null,
                child: Container(
                  width: w,
                  constraints: const BoxConstraints(minHeight: minTouch + 44),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                  decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.md)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: hazardColorOf(type), shape: BoxShape.circle),
                      child: Icon(iconFor(hazardIconKey(type)), size: 24, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(texts.hazardLabel(type), textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
                  ]),
                ),
              ),
            ),
          ),
      ]);
    });
  }
}
