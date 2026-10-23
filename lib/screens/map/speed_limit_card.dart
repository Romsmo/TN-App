import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tn_core/tn_core.dart';

import '../../app_scope.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../common.dart' show Hint;
import 'report_sheet.dart' show ChoiceChip2;

enum _FormKind { missing, wrong }

/// The bottom card of the "speed limit" mode: what is on record at the tapped spot, and - when standing - adding or
/// correcting it. Adding a limit names a stretch of road by its two ends: the first tap is the spot, the second end is
/// picked on the map next (the parent routes that tap to [spotEnd]).
class SpeedLimitCard extends StatefulWidget {
  const SpeedLimitCard({
    super.key,
    required this.service,
    required this.spot,
    required this.spotEnd,
    required this.unit,
    required this.locked,
    required this.onSaved,
    required this.onClose,
    required this.onWantsEnd,
  });

  final TnService? service;

  /// The tapped spot; null = nothing tapped yet.
  final Spot? spot;

  /// The other end of a stretch of road, once picked.
  final Spot? spotEnd;
  final SpeedUnit unit;

  /// The speed lock (Fahrsperre) is in force: the limit may be read, but not proposed.
  final bool locked;

  /// A proposal was stored, so the map screen can send it.
  final VoidCallback onSaved;
  final VoidCallback onClose;

  /// The card waits for (true) or no longer needs (false) the second end of a stretch.
  final ValueChanged<bool> onWantsEnd;

  @override
  State<SpeedLimitCard> createState() => _SpeedLimitCardState();
}

class _SpeedLimitCardState extends State<SpeedLimitCard> {
  LookupState _state = const LookupLoading();
  _FormKind? _form;
  final _value = TextEditingController();
  CorrectionReason _reason = CorrectionReason.wrongValue;
  ProposalOutcome? _outcome;
  bool _saved = false;
  int _lookups = 0;
  ({IntervalPreview? preview, ProposalProblem? problem})? _preview;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  @override
  void didUpdateWidget(SpeedLimitCard old) {
    super.didUpdateWidget(old);
    if (old.spotEnd != widget.spotEnd) {
      _preview = null;
      if (widget.spotEnd != null) _loadPreview();
    }
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final service = widget.service;
    final spot = widget.spot;
    if (service == null || spot == null) return;
    final n = ++_lookups;
    setState(() => _state = const LookupLoading());
    final next = await lookupSpot(service, spot);
    if (mounted && n == _lookups) setState(() => _state = next);
  }

  Future<void> _loadPreview() async {
    final service = widget.service;
    final a = widget.spot;
    final b = widget.spotEnd;
    if (service == null || a == null || b == null) return;
    setState(() => _previewing = true);
    final r = await previewInterval(service, a, b);
    if (mounted && widget.spotEnd == b) {
      setState(() {
        _preview = r;
        _previewing = false;
      });
    }
  }

  int? get _parsed => parseLimitValue(_value.text, widget.unit);

  void _setForm(_FormKind? kind) {
    setState(() {
      _form = kind;
      _outcome = null;
      _saved = false;
      _preview = null;
    });
    widget.onWantsEnd(kind == _FormKind.missing);
  }

  Future<void> _send() async {
    final service = widget.service;
    final spot = widget.spot;
    final parsed = _parsed;
    final form = _form;
    if (service == null || spot == null || form == null || parsed == null) return;
    final ProposalOutcome result;
    if (form == _FormKind.missing) {
      final end = widget.spotEnd;
      if (end == null) return;
      result = await proposeMissing(service, spot, end, parsed, widget.unit);
    } else {
      result = await proposeCorrection(service, spot, parsed, widget.unit, _reason);
    }
    if (!mounted) return;
    if (result.ok) {
      setState(() {
        _saved = true;
        _outcome = null;
        _form = null;
      });
      widget.onWantsEnd(false);
      widget.onSaved();
      _lookup();
    } else {
      setState(() => _outcome = result);
      if (result.reason == ProposalProblem.roadAlreadyHasLimit) {
        setState(() => _form = null);
        widget.onWantsEnd(false);
        _lookup();
      }
    }
  }

  String _origin(LimitFound f) {
    final o = f.answer.origin;
    return switch (o) {
      ImportedOrigin() => context.t('limit.origin.imported'),
      LocallyProposed() => context.t('limit.origin.locallyProposed'),
      CommunityCorrected() => context.t('limit.origin.communityCorrected', {'count': o.confirmations}),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final unit = widget.unit;
    final result = _state is LookupDone ? (_state as LookupDone).result : null;
    final canPropose = result is LimitFound || result is LimitNotRecorded;
    final parsed = _parsed;
    final needsEnd = _form == _FormKind.missing && widget.spotEnd == null;
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.sheet), boxShadow: elevation(context, 2)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(3)))),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.speed, size: 24, color: c.tint),
                const SizedBox(width: 10),
                Expanded(child: Semantics(header: true, child: Text(context.t('limit.title'), style: TnText.heading.copyWith(color: c.text)))),
                Semantics(
                  button: true,
                  label: context.t('limit.close'),
                  child: GestureDetector(
                    onTap: () {
                      widget.onWantsEnd(false);
                      widget.onClose();
                    },
                    child: Container(
                      width: minTouch - 8,
                      height: minTouch - 8,
                      decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
                      child: Icon(Icons.close, size: 20, color: c.text),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              if (widget.spot == null) Text(context.t('limit.tapRoad'), style: TnText.body.copyWith(color: c.textSecondary)),
              if (widget.spot != null && _state is LookupLoading) Text(context.t('limit.loading'), style: TnText.body.copyWith(color: c.textSecondary)),
              if (_state is LookupError)
                Semantics(liveRegion: true, child: Text(context.t('limit.error'), style: TnText.body.copyWith(color: c.text))),
              if (result is LimitFound)
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(
                    label: context.t('limit.found', {'value': result.answer.value, 'unit': unitLabel(result.answer.unit)}),
                    child: ExcludeSemantics(
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: '${result.answer.value} ', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: c.text)),
                        TextSpan(text: unitLabel(result.answer.unit), style: TnText.caption.copyWith(color: c.textSecondary)),
                      ])),
                    ),
                  ),
                  Hint(_origin(result)),
                ]),
              if (result is LimitNotRecorded) Text(context.t('limit.notRecorded'), style: TnText.body.copyWith(color: c.text)),
              if (result is LimitOutsideOfflineArea)
                Semantics(liveRegion: true, child: Text(context.t('limit.outside'), style: TnText.body.copyWith(color: c.text))),
              if (canPropose && _form == null) ...[
                const SizedBox(height: 10),
                if (widget.locked)
                  Semantics(
                    liveRegion: true,
                    child: Row(children: [
                      Icon(Icons.lock, size: 18, color: c.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(child: Hint(context.t('limit.locked'))),
                    ]),
                  )
                else if (result is LimitNotRecorded)
                  PrimaryButton(label: context.t('limit.add'), onPressed: () => _setForm(_FormKind.missing))
                else
                  SoftButton(label: context.t('limit.wrong'), onPressed: () => _setForm(_FormKind.wrong)),
              ],
              if (_form != null && !widget.locked) ...[
                const SizedBox(height: 10),
                if (needsEnd) ...[
                  Semantics(liveRegion: true, child: Text(context.t('limit.interval.pickEnd'), style: TnText.body.copyWith(color: c.text))),
                  const SizedBox(height: 8),
                  SoftButton(label: context.t('limit.cancel'), onPressed: () => _setForm(null)),
                ] else ...[
                  if (_form == _FormKind.missing) ...[
                    if (_previewing) Hint(context.t('limit.loading')),
                    if (_preview?.preview != null)
                      Hint(_preview!.preview!.road != null && _preview!.preview!.lengthM != null
                          ? context.t('limit.interval.preview', {'road': _preview!.preview!.road!, 'length': _preview!.preview!.lengthM!.round()})
                          : _preview!.preview!.lengthM != null
                              ? context.t('limit.interval.previewLength', {'length': _preview!.preview!.lengthM!.round()})
                              : ''),
                    if (_preview?.problem != null)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _preview!.problem == ProposalProblem.network ? context.t('limit.interval.previewFailed') : context.t('limit.error.${_preview!.problem!.name}'),
                          style: TnText.caption.copyWith(color: c.text),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                  Semantics(header: true, child: Text(context.t('limit.form.value', {'unit': unitLabel(unit)}).toUpperCase(), style: TnText.label.copyWith(color: c.textSecondary))),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    for (final q in quickLimits[unit]!)
                      ChoiceChip2(label: '$q', selected: parsed == q, onTap: () => setState(() => _value.text = '$q')),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _value,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                        decoration: InputDecoration(hintText: unitLabel(unit)),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ]),
                  if (_form == _FormKind.wrong) ...[
                    const SizedBox(height: 8),
                    Semantics(header: true, child: Text(context.t('limit.form.reason').toUpperCase(), style: TnText.label.copyWith(color: c.textSecondary))),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final r in wrongReasons)
                        ChoiceChip2(label: context.t('limit.reason.${r.name}'), selected: _reason == r, onTap: () => setState(() => _reason = r)),
                    ]),
                  ],
                  const SizedBox(height: 8),
                  Text(context.t('limit.safety'), style: TnText.caption.copyWith(color: c.text, fontWeight: FontWeight.w600)),
                  Hint(_form == _FormKind.missing ? context.t('limit.privacy.interval') : context.t('limit.privacy')),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: PrimaryButton(label: context.t('limit.send'), onPressed: parsed == null ? null : _send)),
                    const SizedBox(width: 10),
                    Expanded(child: SoftButton(label: context.t('limit.cancel'), onPressed: () => _setForm(null))),
                  ]),
                ],
              ],
              if (_saved)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Semantics(liveRegion: true, child: Text(context.t('limit.saved'), style: TnText.body.copyWith(color: c.success))),
                )
              else if (_outcome != null && !_outcome!.ok)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Semantics(liveRegion: true, child: Text(context.t('limit.error.${_outcome!.reason!.name}'), style: TnText.body.copyWith(color: c.text))),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
