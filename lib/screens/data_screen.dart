import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tn_core/tn_core.dart';

import '../app_scope.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'common.dart';

/// "Offline-Daten": the offline area (automatic or own regions), the storage and its limit, "Wi-Fi only" and the download.
class DataScreen extends StatefulWidget {
  const DataScreen({super.key});

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  int _reloads = 0;
  OfflineView? _view;
  BootstrapPlan? _plan;
  bool _planKnown = false;
  TnService? _readFor;
  int _readVersion = -1;

  void _maybeRead(TnService? service, int version) {
    if (service == null) return;
    final key = version + _reloads;
    if (identical(service, _readFor) && key == _readVersion) return;
    _readFor = service;
    _readVersion = key;
    unawaited(() async {
      final view = await loadOfflineView(service);
      BootstrapPlan? plan;
      try {
        plan = await service.planBootstrap();
      } catch (_) {}
      if (!mounted || !identical(_readFor, service) || _readVersion != key) return;
      setState(() {
        _view = view;
        _plan = plan;
        _planKnown = true;
      });
    }());
  }

  /// Stores the choice, then lets the next sync apply it (it respects "Wi-Fi only").
  Future<void> _choose(Future<Object?> Function(TnService service) change) async {
    final tn = context.app.tn;
    final service = tn.service;
    if (service == null) return;
    try {
      await change(service);
    } catch (_) {
      // the screen re-reads below and shows what is really stored
    }
    if (!mounted) return;
    setState(() => _reloads++);
    unawaited(tn.syncNow().then((_) {
      if (mounted) setState(() => _reloads++);
    }));
  }

  Future<void> _load(bool ignoreWifi) async {
    await context.app.tn.syncNow(ignoreWifi: ignoreWifi);
    if (mounted) setState(() => _reloads++);
  }

  String _limitLabel(int? maxBytes) => maxBytes == null ? context.t('offline.limitNone') : context.app.texts.formatBytes(maxBytes);

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return ListenableBuilder(
      listenable: Listenable.merge([app.settings, app.tn]),
      builder: (context, _) {
        final snap = app.tn.snapshot;
        _maybeRead(snap.service, snap.dataVersion);
        final view = _view;
        final settings = view?.settings;
        final texts = app.texts;
        final wifiOnly = app.settings.value.dataWifiOnly;
        return SubPage(
          title: context.t('data.title'),
          children: [
            if (settings != null)
              CardSection(title: context.t('offline.mode'), children: [
                Segments<String>(
                  value: settings.mode == OfflineMode.auto ? 'auto' : 'regions',
                  options: {'auto': context.t('offline.mode.auto'), 'regions': context.t('offline.mode.regions')},
                  onChanged: (mode) {
                    if (mode == 'auto') _choose((s) => s.setOfflineRegions(mode: OfflineMode.auto));
                  },
                ),
                Hint(settings.mode == OfflineMode.auto
                    ? context.t('offline.auto.hint')
                    : settings.mode == OfflineMode.all
                        ? context.t('offline.all.hint')
                        : context.t('offline.regions.hint')),
                if (settings.mode == OfflineMode.auto && view?.plan?.needsLocation == true) Body(context.t('status.needsLocation')),
              ]),
            if (view?.usage != null)
              CardSection(title: context.t('offline.storage'), children: [
                Body(context.t('offline.used', {'size': texts.formatBytes(usedBytes(view!.usage!))})),
                Hint(context.t('offline.limit', {'limit': _limitLabel(settings?.maxBytes ?? view.usage!.maxBytes)})),
                Semantics(
                  label: context.t('offline.limitChoose'),
                  child: Column(children: [
                    for (final choice in limitChoices)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.sm),
                        child: Semantics(
                          selected: (settings?.maxBytes) == choice,
                          child: (settings?.maxBytes) == choice
                              ? PrimaryButton(label: _limitLabel(choice), onPressed: () => _choose((s) => s.setStorageLimits(maxBytes: choice, clearMaxBytes: choice == null)))
                              : SoftButton(label: _limitLabel(choice), onPressed: () => _choose((s) => s.setStorageLimits(maxBytes: choice, clearMaxBytes: choice == null))),
                        ),
                      ),
                  ]),
                ),
                if (view.plan != null && !view.plan!.fits) Body(context.t('offline.doesNotFit')),
              ]),
            if (view != null)
              CardSection(title: context.t('offline.regions'), children: [
                if (view.regions != null && settings != null)
                  if (view.regions!.isEmpty)
                    Hint(context.t('offline.regions.none'))
                  else
                    for (final region in view.regions!)
                      _regionRow(context, region, settings)
                else if (view.needsConnection)
                  Hint(context.t('offline.needsConnection'))
                else
                  Hint(context.t('data.unknown')),
                Hint(context.t('offline.regions.warn')),
              ]),
            CardSection(children: [
              SwitchRow(
                leading: const IconTile(icon: Icons.wifi, color: Color(0xFF007AFF)),
                title: context.t('data.wifiOnly'),
                value: wifiOnly,
                onChanged: (v) => app.settings.update((s) => s.copyWith(dataWifiOnly: v)),
              ),
              Hint(context.t('data.wifiOnlyHint')),
            ]),
            CardSection(children: [
              if (!_planKnown || _plan == null)
                Hint(context.t('data.unknown'))
              else if (_plan!.bytesPending == 0)
                Body(context.t('data.complete'))
              else
                Body(context.t('data.pending', {'size': texts.formatBytes(_plan!.bytesPending)})),
              if (snap.sync?.storageBytes != null) Hint(context.t('data.stored', {'size': texts.formatBytes(snap.sync!.storageBytes!)})),
              if (_plan != null && _plan!.bytesPending > 0) ...[
                PrimaryButton(label: context.t('data.loadNow'), onPressed: () => _load(false)),
                if (snap.waitingForWifi) SoftButton(label: context.t('data.loadAnyway'), onPressed: () => _load(true)),
              ],
              Hint(context.t('offline.onlineOnly')),
            ]),
          ],
        );
      },
    );
  }

  Widget _regionRow(BuildContext context, OfflineRegion region, OfflineSettings settings) {
    final texts = context.app.texts;
    final chosen = settings.mode == OfflineMode.regions ? settings.regions.contains(region.id) : region.selected;
    final leaving = isLeaving(region, settings);
    final state = leaving
        ? context.t('offline.region.leaving')
        : switch (region.state) {
            RegionState.complete => context.t('offline.region.complete'),
            RegionState.partial => context.t('offline.region.partial'),
            RegionState.none => context.t('offline.region.none'),
          };
    final size = '${region.complete ? '' : '${context.t('offline.atLeast')} '}${texts.formatBytes(region.estimatedDeviceBytes)}';
    final name = regionName(region, texts.language, builtInCountryName);
    return MergeSemantics(
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Body(name),
            Hint('$size · $state'),
          ]),
        ),
        Semantics(
          label: context.t('offline.region.keep', {'name': name}),
          child: Switch(
            value: chosen,
            onChanged: (_) => _choose((s) => s.setOfflineRegions(regions: toggleRegion(settings.regions, region.id))),
          ),
        ),
      ]),
    );
  }
}
