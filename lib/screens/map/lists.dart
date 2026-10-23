import 'package:flutter/material.dart';
import 'package:tn_core/tn_core.dart';

import '../../app_scope.dart';
import '../../ui/icons.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../common.dart' show Hint;
import '../drive_screen.dart' show hazardColorOf;

/// The chips above the map: one per type in the data (the list comes from the data, not from the app). A hidden type stays
/// as a chip so it can always be switched back on.
class FilterBar extends StatelessWidget {
  const FilterBar({super.key, required this.types, required this.hidden, required this.onToggle});
  final List<String> types;
  final List<String> hidden;
  final void Function(String type) onToggle;

  @override
  Widget build(BuildContext context) {
    if (types.isEmpty) return const SizedBox.shrink();
    final texts = context.app.texts;
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        itemCount: types.length,
        separatorBuilder: (_, i) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final type = types[i];
          return Center(
            child: FilterPill(
              label: texts.hazardLabel(type),
              color: hazardColorOf(type),
              icon: iconFor(hazardIconKey(type)),
              on: !hidden.contains(type),
              onTap: () => onToggle(type),
            ),
          );
        },
      ),
    );
  }
}

/// The reports of the visible area as a list, nearest first: an entrance for screen readers.
class ReportList extends StatelessWidget {
  const ReportList({super.key, required this.items, required this.onSelect});
  final List<NearbyItem> items;
  final void Function(String id) onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final texts = context.app.texts;
    final sorted = [...items]..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    if (sorted.isEmpty) {
      return Padding(padding: const EdgeInsets.all(Space.xl), child: Center(child: Hint(context.t('map.listEmpty'))));
    }
    return Column(children: [
      for (final item in sorted)
        Semantics(
          button: true,
          label: item is HazardItem
              ? context.t('map.listRow', {'type': texts.hazardLabel(item.hazardType), 'meters': item.distanceMeters.round(), 'count': item.confirmCount})
              : context.t('map.listRowCamera', {'type': texts.hazardLabel(pointType(item)), 'meters': item.distanceMeters.round()}),
          excludeSemantics: true,
          child: InkWell(
            onTap: () => onSelect(item.id),
            child: Container(
              constraints: const BoxConstraints(minHeight: minTouch),
              padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: hazardColorOf(pointType(item)), shape: BoxShape.circle),
                  child: Icon(iconFor(hazardIconKey(pointType(item))), size: 20, color: Colors.white),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(texts.hazardLabel(pointType(item)), style: TnText.body.copyWith(color: c.text, fontWeight: FontWeight.w600)),
                    Text('${item.distanceMeters.round()} m', style: TnText.caption.copyWith(color: c.textSecondary)),
                  ]),
                ),
                if (item is HazardItem) Hint('${item.confirmCount}'),
              ]),
            ),
          ),
        ),
    ]);
  }
}
