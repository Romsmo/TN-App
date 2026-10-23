import 'dart:async';

import '../drive_host.dart';
import '../fix.dart';
import 'route.dart';
import 'sim_data.dart';

/// The demo route as a position source: one fix per second of simulated time, [speedup] times faster than real time.
PositionSource createSimSource(int speedup, {void Function()? onFinished, int Function()? clock}) =>
    _SimSource(speedup < 1 ? 1 : speedup, onFinished, clock ?? () => DateTime.now().millisecondsSinceEpoch);

class _SimSource implements PositionSource {
  _SimSource(this._speedup, this._onFinished, this._clock);
  final int _speedup;
  final void Function()? _onFinished;
  final int Function() _clock;
  Timer? _timer;

  @override
  Future<void> start(void Function(Fix fix) onFix) async {
    final player = RoutePlayer(demoRoute, simSpeedAt, _clock());
    _timer = Timer.periodic(Duration(milliseconds: (1000 / _speedup).round()), (timer) {
      final fix = player.next();
      if (fix == null) {
        timer.cancel();
        _timer = null;
        _onFinished?.call();
        return;
      }
      onFix(Fix(lat: fix.lat, lng: fix.lng, speedKmh: fix.speedKmh, heading: fix.heading, t: _clock()));
    });
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
