import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tn_core/tn_core.dart';

import '../../app_scope.dart';
import '../../services/location.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../common.dart';
import '../server_screen.dart';
import 'detail_card.dart';
import 'lists.dart';
import 'map_view.dart';
import 'report_sheet.dart';
import 'speed_limit_card.dart';

/// The "Karte" tab: the map with the reports around, the filter, the reporting sheet and the speed-limit mode.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.active});

  /// Whether the tab is on screen: the position is read only then.
  final bool active;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapHandle _handle = MapHandle();

  ({double lat, double lng, double radius})? _viewport;
  List<NearbyItem> _items = const [];
  Object? _readKey;
  int _readSeq = 0;

  String? _selectedId;
  bool _located = false;
  bool _listMode = false;
  FollowMode _follow = FollowMode.off;
  bool _reporting = false;

  // "Speed limit" mode: tap a road to see its limit, or add or correct it (only when not driving).
  bool _limitMode = false;
  Spot? _limitSpot;
  Spot? _limitEnd;
  bool _limitWantsEnd = false;

  bool _locating = false;
  ({double lat, double lng})? _draft;
  String? _reportMessage;
  String? _notice;
  Timer? _noticeTimer;
  ({String id, VoteState state})? _vote;
  // Local writes show up at once (optimistic view), before any sync reports a change.
  int _localChanges = 0;

  DevicePosition get _position => context.app.position;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPosition());
  }

  @override
  void didUpdateWidget(MapScreen old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _syncPosition();
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _position.removeListener(_onPosition);
    super.dispose();
  }

  bool _listening = false;

  /// Reads the position while the tab is shown: silently, and only if the permission was granted before.
  Future<void> _syncPosition() async {
    final pos = _position;
    if (widget.active) {
      if (!_listening) {
        pos.addListener(_onPosition);
        _listening = true;
      }
      final started = await pos.start();
      if (started && mounted) setState(() => _located = true);
    } else if (_listening) {
      pos.removeListener(_onPosition);
      _listening = false;
      await pos.stop();
    }
  }

  bool _firstFixSeen = false;

  void _onPosition() {
    final fix = _position.fix;
    if (fix == null || !mounted) return;
    if (!_firstFixSeen) {
      _firstFixSeen = true;
      _located = true;
      _handle.flyTo(fix.lat, fix.lng, zoom: 12, ms: 800);
      // Tells the library which tiles to watch: a coarse position, once, from the map.
      unawaited(context.app.tn.service?.updatePosition(fix.lat, fix.lng).then<Object?>((_) => null).catchError((_) => null) ?? Future.value());
    }
    // A following map moves with every new position (a centred one moved once, when the button was pressed).
    if (shouldMoveWithPosition(_follow)) _handle.flyTo(fix.lat, fix.lng, zoom: centerZoom, ms: 600);
    setState(() {});
  }

  Future<void> _locate({required bool ask}) async {
    final started = await _position.start(ask: ask);
    if (!started) return;
    if (mounted) setState(() => _located = true);
    final fix = _position.fix;
    if (fix != null) {
      _handle.flyTo(fix.lat, fix.lng, zoom: 12, ms: 800);
    }
  }

  void _showNotice(String text) {
    setState(() => _notice = text);
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  Future<void> _pressFollow() async {
    final fix = _position.fix;
    if (fix == null) {
      await _locate(ask: true);
      if (mounted) setState(() => _follow = FollowMode.centered);
      return;
    }
    final next = nextFollowMode(_follow);
    setState(() => _follow = next);
    if (next != FollowMode.off) _handle.flyTo(fix.lat, fix.lng, zoom: centerZoom, ms: 600);
  }

  void _openLimit() {
    setState(() {
      _reporting = false;
      _draft = null;
      _selectedId = null;
      _notice = null;
      _limitSpot = null;
      _limitEnd = null;
      _limitWantsEnd = false;
      _limitMode = true;
    });
  }

  void _closeLimit() => setState(() {
        _limitMode = false;
        _limitSpot = null;
        _limitEnd = null;
        _limitWantsEnd = false;
      });

  void _openReport() {
    _closeLimit();
    setState(() {
      _reporting = true;
      _selectedId = null;
      _reportMessage = null;
      _notice = null;
    });
    if (_position.fix == null) {
      setState(() => _locating = true);
      _locate(ask: true).whenComplete(() {
        if (mounted) setState(() => _locating = false);
      });
    }
  }

  void _closeReport() => setState(() {
        _reporting = false;
        _draft = null;
        _reportMessage = null;
      });

  ReportLocation get _reportLocation {
    final d = _draft;
    if (d != null) return (lat: d.lat, lng: d.lng, fromMap: true);
    final fix = _position.fix;
    if (fix != null) return (lat: fix.lat, lng: fix.lng, fromMap: false);
    return null;
  }

  Future<void> _pickType(String type, DurationChoice choice) async {
    final app = context.app;
    final service = app.tn.service;
    final loc = _reportLocation;
    if (service == null || loc == null) return;
    final outcome = await submitHazard(service, type, (lat: loc.lat, lng: loc.lng), choice);
    if (!mounted) return;
    if (!outcome.ok) {
      setState(() => _reportMessage = submitErrorText(app.texts, outcome));
      return;
    }
    _closeReport();
    _showNotice(outcome.durationHonoured == false ? context.t('report.savedDefaultDuration') : context.t('report.saved'));
    setState(() => _localChanges++);
    unawaited(app.tn.syncNow()); // sends right away when allowed; otherwise the pending note explains the wait
  }

  Future<void> _castVote(NearbyItem selected, bool stillThere) async {
    final app = context.app;
    final service = app.tn.service;
    if (service == null || selected is! HazardItem) return;
    final outcome = await voteOnReport(service, selected.id, stillThere);
    if (!mounted) return;
    setState(() => _vote = (id: selected.id, state: outcome.ok ? VoteState.saved : VoteState.failed));
    if (outcome.ok) {
      setState(() => _localChanges++);
      unawaited(app.tn.syncNow());
    }
  }

  Future<void> _removeCamera(NearbyItem selected) async {
    final app = context.app;
    final service = app.tn.service;
    if (service == null || selected is! CameraItem) return;
    final outcome = await reportCameraGone(service, selected.id);
    if (!mounted) return;
    setState(() => _vote = (id: selected.id, state: outcome.ok ? VoteState.saved : VoteState.failed));
    if (outcome.ok) {
      setState(() => _localChanges++);
      unawaited(app.tn.syncNow());
    }
  }

  void _onMapPress(double lat, double lng) {
    setState(() {
      if (_reporting) {
        _draft = (lat: lat, lng: lng);
      } else if (_limitMode) {
        if (_limitWantsEnd && _limitSpot != null) {
          _limitEnd = (lat: lat, lng: lng);
        } else {
          _limitSpot = (lat: lat, lng: lng);
          _limitEnd = null;
          _limitWantsEnd = false; // the card for the new spot starts clean
        }
      } else {
        _selectedId = null;
      }
    });
  }

  void _toggleType(String type) {
    final settings = context.app.settings;
    final hidden = {...settings.value.hiddenHazardTypes};
    hidden.contains(type) ? hidden.remove(type) : hidden.add(type);
    settings.update((s) => s.copyWith(hiddenHazardTypes: hidden.toList()));
  }

  /// Reads the items around the viewport from the local store when the viewport or the stored data changed; the previous
  /// result stays on screen meanwhile (no flicker).
  void _maybeRead(TnService? service, int dataVersion) {
    final vp = _viewport;
    if (service == null || vp == null) return;
    final key = (service, vp.lat, vp.lng, vp.radius, dataVersion + _localChanges);
    if (_readKey == key) return;
    _readKey = key;
    final seq = ++_readSeq;
    unawaited(() async {
      List<NearbyItem> items;
      try {
        items = await service.getNearby(vp.lat, vp.lng, vp.radius);
      } catch (_) {
        items = const []; // e.g. before the first sync: an empty map is the honest answer
      }
      if (mounted && seq == _readSeq) setState(() => _items = items);
    }());
  }

  String? _bannerText(ConnectionSnapshot s) {
    final texts = context.app.texts;
    if (s.emergency != null) return null; // the emergency card says it (and more)
    if (s.phase == Phase.starting) return texts.t('status.starting');
    if (s.phase == Phase.noCredentials) return texts.t('status.noCredentials');
    if (s.phase == Phase.error) return texts.t('status.error', {'message': s.error ?? texts.t('common.unknown')});
    if (s.waitingForWifi) return texts.t('status.waitingForWifi');
    if (s.needsLocation) return texts.t('status.needsLocation');
    if (s.sync?.connection == Connection.offline) return texts.t('status.offline');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: Listenable.merge([app.tn, app.settings, app.drive]),
      builder: (context, _) {
        final snap = app.tn.snapshot;
        final s = app.settings.value;
        final policy = app.tn.policy;
        _maybeRead(snap.service, snap.dataVersion);
        final hiddenSet = {...s.hiddenHazardTypes};
        final data = toMapData(_items, hiddenHazardTypes: hiddenSet);
        final visibleHazards = [
          for (final i in _items)
            if ((i is HazardItem && !isTypeHidden(i.hazardType, hiddenSet)) || (i is CameraItem && !isTypeHidden(i.cameraType, hiddenSet))) i,
        ];
        final filterTypes = ({...hazardTypesIn(_items), ...s.hiddenHazardTypes}.toList()..sort());
        NearbyItem? selected;
        for (final i in _items) {
          if ((i is HazardItem || i is CameraItem) && i.id == _selectedId) selected = i;
        }

        final fix = _position.fix;
        final user = _located && fix != null
            ? UserMark(lat: fix.lat, lng: fix.lng, heading: fix.heading, accuracyM: _position.accuracyM)
            : null;

        final banner = _bannerText(snap);
        final pending = pendingText(app.texts, pending: snap.sync?.pendingWrites ?? 0, waitingForWifi: snap.waitingForWifi, offline: snap.sync?.connection == Connection.offline);
        final rejected = rejectedText(app.texts, snap.rejectedWrites);
        final notes = <Widget>[
          if (banner != null) Notice(text: banner, icon: Icons.info),
          if (pending != null) Notice(text: pending, icon: Icons.schedule, color: c.warn),
          if (_notice != null) Notice(text: _notice!, icon: Icons.check_circle, color: c.success),
          if (rejected != null) Notice(text: rejected, icon: Icons.info_outline, action: app.tn.dismissRejected, actionLabel: context.t('rejected.dismiss')),
        ];

        final limitLocked = entryLocked(
          lockActive: app.drive.lockActive,
          lockEnabled: s.driveLockEnabled,
          deviceSpeedKmh: fix?.speedKmh,
        );

        Widget? detail;
        if (selected != null && !_reporting && !_limitMode) {
          final sel = selected;
          detail = DetailCard(
            key: ValueKey(sel.id),
            item: sel,
            onClose: () => setState(() => _selectedId = null),
            onVote: sel is HazardItem ? (still) => _castVote(sel, still) : null,
            onRemoveCamera: sel is CameraItem ? () => _removeCamera(sel) : null,
            voteState: _vote?.id == sel.id ? _vote!.state : VoteState.idle,
          );
        }

        final draft = _reporting ? _draft : (_limitMode ? _limitSpot : null);
        final interval = _limitMode && _limitSpot != null && _limitEnd != null ? [_limitSpot!, _limitEnd!] : null;

        return Stack(
          children: [
            Positioned.fill(
              child: Offstage(
                offstage: _listMode,
                child: TnMapView(
                  data: data,
                  background: c.surfaceAlt,
                  dark: dark,
                  handle: _handle,
                  user: user,
                  onViewport: (lat, lng, radius) {
                    if (!mounted) return;
                    setState(() => _viewport = (lat: lat, lng: lng, radius: radius));
                  },
                  onSelectHazard: (id) {
                    if (!_reporting && !_limitMode) setState(() => _selectedId = id);
                  },
                  onMapPress: _onMapPress,
                  onUserMove: () {
                    if (_follow != FollowMode.off) setState(() => _follow = afterUserMove(_follow));
                  },
                  draft: draft,
                  draftEnd: _limitMode ? _limitEnd : null,
                  interval: interval,
                ),
              ),
            ),
            if (_listMode)
              Positioned.fill(
                child: ColoredBox(
                  color: c.background,
                  child: ListView(
                    padding: const EdgeInsets.only(top: 190, bottom: tabBarClearance + 16),
                    children: [ReportList(items: visibleHazards, onSelect: (id) => setState(() => _selectedId = id))],
                  ),
                ),
              ),
            Positioned.fill(
              child: SafeArea(
                bottom: false,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: Space.sm),
                        FilterBar(types: filterTypes, hidden: s.hiddenHazardTypes, onToggle: _toggleType),
                        if (snap.emergency != null) ...[
                          const SizedBox(height: Space.sm),
                          EmergencyCard(
                            reason: snap.emergency!,
                            onRetry: () => app.tn.syncNow(ignoreWifi: true),
                            onSetup: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LockGuard(child: ServerScreen()))),
                          ),
                        ],
                        for (final n in notes)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
                            child: Align(alignment: Alignment.centerLeft, child: n),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, tabBarClearance),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!_reporting && !_limitMode)
                            Align(
                              alignment: Alignment.centerRight,
                              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                                RoundButton(
                                  icon: _listMode ? Icons.map : Icons.format_list_bulleted,
                                  label: _listMode ? context.t('map.showMap') : context.t('map.list'),
                                  onPressed: () => setState(() => _listMode = !_listMode),
                                ),
                                const SizedBox(height: 12),
                                RoundButton(
                                  icon: _follow == FollowMode.off ? Icons.location_searching : _follow == FollowMode.centered ? Icons.my_location : Icons.navigation,
                                  label: context.t('map.follow.${_follow.name}'),
                                  active: _follow == FollowMode.follow,
                                  onPressed: _pressFollow,
                                ),
                                const SizedBox(height: 12),
                                RoundButton(icon: Icons.speed, label: context.t('limit.fab'), onPressed: _openLimit),
                                const SizedBox(height: 12),
                                Semantics(
                                  button: true,
                                  label: context.t('report.open'),
                                  child: GestureDetector(
                                    onTap: _openReport,
                                    child: Container(
                                      height: 56,
                                      padding: const EdgeInsets.symmetric(horizontal: 20),
                                      decoration: BoxDecoration(color: c.tint, borderRadius: BorderRadius.circular(28), boxShadow: elevation(context, 2)),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(Icons.add, size: 26, color: c.onTint),
                                        const SizedBox(width: 6),
                                        Text(context.t('report.open'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.onTint)),
                                      ]),
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                          if (!_reporting && !_limitMode) const SizedBox(height: 10),
                          ?detail,
                          if (_limitMode)
                            SpeedLimitCard(
                              key: ValueKey(_limitSpot == null ? 'none' : '${_limitSpot!.lat},${_limitSpot!.lng}'),
                              service: snap.service,
                              spot: _limitSpot,
                              spotEnd: _limitEnd,
                              unit: s.speedUnit,
                              locked: limitLocked,
                              onWantsEnd: (v) => WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                setState(() {
                                  _limitWantsEnd = v;
                                  if (!v) _limitEnd = null;
                                });
                              }),
                              onSaved: () {
                                setState(() => _localChanges++);
                                unawaited(app.tn.syncNow());
                              },
                              onClose: _closeLimit,
                            ),
                          if (_reporting)
                            ReportSheet(
                              types: mapReportTypes(s.camerasEnabled && policy?.active == true, policy?.maxLevel),
                              location: _reportLocation,
                              locating: _locating,
                              message: _reportMessage,
                              onPick: _pickType,
                              onCancel: _closeReport,
                            ),
                          Padding(
                            padding: const EdgeInsets.only(left: 4, top: 6),
                            child: Semantics(
                              label: mapAttribution,
                              child: Text(context.t('map.attribution'), style: TextStyle(fontSize: 11, color: c.textSecondary)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Used where a screen needs to know whether a position was ever read.
bool hasPosition(DevicePosition p) => p.fix != null;
