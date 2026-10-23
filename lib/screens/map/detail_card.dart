import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tn_core/tn_core.dart';

import '../../app_scope.dart';
import '../../ui/icons.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../common.dart';
import '../drive_screen.dart' show hazardColorOf;

enum VoteState { idle, saved, failed }

/// A bottom sheet with the details of one report: kind, how sure the community is, how long it stays.
class DetailCard extends StatefulWidget {
  const DetailCard({super.key, required this.item, required this.onClose, this.onVote, this.onRemoveCamera, this.voteState = VoteState.idle});
  final NearbyItem item;
  final VoidCallback onClose;

  /// Votes "still there" (`true`) or "gone" (`false`). Without it the card has no voting (read-only).
  final void Function(bool stillThere)? onVote;

  /// Reports "this permanently installed device is gone". Without it the card has no such action.
  final VoidCallback? onRemoveCamera;
  final VoteState voteState;

  @override
  State<DetailCard> createState() => _DetailCardState();
}

class _DetailCardState extends State<DetailCard> {
  Timer? _timer;
  int _now = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    // the remaining lifetime is refreshed once a minute while the card is shown
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => setState(() => _now = DateTime.now().millisecondsSinceEpoch));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final item = widget.item;
    final texts = context.app.texts;
    final kind = pointType(item);
    final isCamera = item is CameraItem;
    final hazard = item is HazardItem ? item : null;
    final left = hazard == null ? null : remainingSeconds(hazard.expiresAt, _now);
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
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: hazardColorOf(kind), shape: BoxShape.circle),
                child: Icon(iconFor(hazardIconKey(kind)), size: 24, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(child: Semantics(header: true, child: Text(texts.hazardLabel(kind), style: TnText.heading.copyWith(color: c.text)))),
              Semantics(
                button: true,
                label: context.t('detail.close'),
                child: GestureDetector(
                  onTap: widget.onClose,
                  child: Container(
                    width: minTouch - 8,
                    height: minTouch - 8,
                    decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
                    child: Icon(Icons.close, size: 20, color: c.text),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            if (isCamera) ...[
              Hint(context.t('detail.camera.fixed')),
              Hint(context.t('detail.distance', {'meters': item.distanceMeters.round()})),
              if (widget.onRemoveCamera != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(context.t('camera.question'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
                    const SizedBox(height: 8),
                    if (widget.voteState == VoteState.saved)
                      Semantics(liveRegion: true, child: Text(context.t('camera.goneThanks'), style: TnText.body.copyWith(color: c.success)))
                    else
                      SoftButton(label: context.t('camera.gone'), onPressed: widget.onRemoveCamera),
                    if (widget.voteState == VoteState.failed)
                      Semantics(liveRegion: true, child: Text(context.t('vote.error'), style: TnText.caption.copyWith(color: c.danger))),
                  ]),
                ),
            ] else if (hazard != null) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                _Count(icon: Icons.check_circle, color: c.success, text: context.t('detail.confirmed', {'count': hazard.confirmCount})),
                _Count(icon: Icons.cancel, color: c.danger, text: context.t('detail.denied', {'count': hazard.denyCount})),
              ]),
              const SizedBox(height: 4),
              if (hazard.expiresAt != null)
                Hint(context.t('detail.validUntil', {
                  'time': DateTime.tryParse(hazard.expiresAt!) != null ? formatDateTime(context, DateTime.parse(hazard.expiresAt!).millisecondsSinceEpoch) : '?',
                })),
              if (left != null) Hint(context.t('detail.remaining', {'time': formatDuration(texts, left)})),
              Hint(context.t('detail.distance', {'meters': hazard.distanceMeters.round()})),
              if (hazard.pending) Text(context.t('detail.pending'), style: TnText.caption.copyWith(color: c.warn)),
              if (widget.onVote != null && !hazard.pending)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(context.t('vote.question'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
                    const SizedBox(height: 8),
                    if (widget.voteState == VoteState.saved)
                      Semantics(liveRegion: true, child: Text(context.t('vote.thanks'), style: TnText.body.copyWith(color: c.success)))
                    else
                      Row(children: [
                        Expanded(child: PrimaryButton(label: context.t('vote.still'), onPressed: () => widget.onVote!(true))),
                        const SizedBox(width: 8),
                        Expanded(child: SoftButton(label: context.t('vote.gone'), onPressed: () => widget.onVote!(false))),
                      ]),
                    if (widget.voteState == VoteState.failed)
                      Semantics(liveRegion: true, child: Text(context.t('vote.error'), style: TnText.caption.copyWith(color: c.danger))),
                  ]),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(text, style: TnText.caption.copyWith(color: c.text)),
      ]),
    );
  }
}
