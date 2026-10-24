import 'dart:async';
import 'dart:typed_data';

import 'package:tn_core/tn_core.dart';
import 'package:tn_display_protocol/tn_display_protocol.dart' as d;
import 'package:universal_ble/universal_ble.dart';

/// The Bluetooth side of the display link on a phone, with `universal_ble` (BSD-3-Clause). It only moves bytes; the connection
/// sequence and every decision are in `tn_core`.
class UniversalBleDisplayTransport implements DisplayTransport {
  final String _service = d.uuidForSlot(d.Slot.service);
  String? _id;
  final StreamController<bool> _conn = StreamController<bool>.broadcast();
  StreamSubscription<bool>? _connSub;

  String _char(int slot) => d.uuidForSlot(slot);

  /// Asks for the Bluetooth permission (the system dialog appears on the first use) and returns whether scanning may start.
  Future<bool> ensureReady() async {
    try {
      if (!await UniversalBle.hasPermissions()) {
        await UniversalBle.requestPermissions();
      }
      final state = await UniversalBle.getBluetoothAvailabilityState();
      return state == AvailabilityState.poweredOn;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<DisplayFound> scan() {
    late StreamController<DisplayFound> c;
    StreamSubscription<BleDevice>? sub;
    c = StreamController<DisplayFound>(
      onListen: () async {
        sub = UniversalBle.scanStream.listen((dev) {
          c.add(DisplayFound(id: dev.deviceId, name: (dev.name ?? '').isEmpty ? 'TN-Display' : dev.name!, rssi: dev.rssi));
        });
        try {
          await UniversalBle.startScan(
            scanFilter: ScanFilter(withServices: [_service]),
            skipDuplicates: true,
          );
        } catch (e) {
          c.addError(e);
        }
      },
      onCancel: () async {
        await sub?.cancel();
        try {
          await UniversalBle.stopScan();
        } catch (_) {}
      },
    );
    return c.stream;
  }

  @override
  Future<void> stopScan() async {
    try {
      await UniversalBle.stopScan();
    } catch (_) {}
  }

  @override
  Future<void> connect(String id) async {
    _id = id;
    await _connSub?.cancel();
    _connSub = UniversalBle.connectionStream(id).listen(_conn.add);
    await UniversalBle.connect(id, timeout: const Duration(seconds: 15));
    await UniversalBle.discoverServices(id);
  }

  @override
  Future<void> disconnect() async {
    final id = _id;
    await _connSub?.cancel();
    _connSub = null;
    if (id == null) return;
    try {
      await UniversalBle.disconnect(id);
    } catch (_) {}
  }

  @override
  Stream<bool> get connection => _conn.stream;

  @override
  Future<int> negotiateMtu() async => UniversalBle.requestMtu(_id!, 247);

  @override
  Future<Uint8List> read(int slot) => UniversalBle.read(_id!, _service, _char(slot));

  @override
  Future<void> write(int slot, Uint8List data, {required bool withResponse}) =>
      UniversalBle.write(_id!, _service, _char(slot), data, withoutResponse: !withResponse);

  @override
  Stream<Uint8List> subscribe(int slot) {
    final id = _id!;
    final char = _char(slot);
    late StreamController<Uint8List> c;
    StreamSubscription<Uint8List>? sub;
    c = StreamController<Uint8List>(
      onListen: () async {
        sub = UniversalBle.characteristicValueStream(id, char).listen(c.add);
        try {
          await UniversalBle.subscribeNotifications(id, _service, char);
        } catch (e) {
          c.addError(e);
        }
      },
      onCancel: () async {
        await sub?.cancel();
        try {
          await UniversalBle.unsubscribe(id, _service, char);
        } catch (_) {}
      },
    );
    return c.stream;
  }
}
