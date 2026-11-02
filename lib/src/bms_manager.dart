import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models.dart';
import 'protocol.dart';
import 'protocol_daly.dart';
import 'protocol_jbd.dart';
import 'protocol_jk.dart';

enum BmsState { idle, scanning, connecting, connected, error }

/// Owns the BLE connection lifecycle: scan, pair, connect, auto-reconnect,
/// protocol detection and telemetry polling.
class BmsManager extends ChangeNotifier {
  BmsState state = BmsState.idle;
  String status = 'Not connected';
  List<ScanCandidate> candidates = [];
  Telemetry? latest;
  String? connectedId;
  String? connectedName;
  BmsProtocol? proto;

  String Function()? _getSavedId;
  void Function(String)? _setSavedId;

  BluetoothDevice? _device;
  Timer? _pollTimer;
  Timer? _cellTimer;
  Timer? _retryTimer;
  int _retry = 0;
  bool _intentionalStop = false;
  bool _connecting = false;
  StreamSubscription<BluetoothConnectionState>? _stateSub;

  final StreamController<Telemetry> _telemetry = StreamController.broadcast();
  Stream<Telemetry> get telemetry => _telemetry.stream;

  void attachStorage({required String Function() getSavedId, required void Function(String) setSavedId}) {
    _getSavedId = getSavedId;
    _setSavedId = setSavedId;
  }

  Future<bool> ensureAdapterOn() async {
    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) return true;
    try {
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 10))
          .first;
      return true;
    } catch (_) {
      try {
        await FlutterBluePlus.turnOn();
        return FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on;
      } catch (_) {
        return false;
      }
    }
  }

  Future<bool> ensurePermissions() async {
    var ok = true;
    if (await Permission.bluetoothScan.isDenied) {
      ok = await Permission.bluetoothScan.request().isGranted && ok;
    }
    if (await Permission.bluetoothConnect.isDenied) {
      ok = await Permission.bluetoothConnect.request().isGranted && ok;
    }
    if (await Permission.location.isDenied) {
      ok = await Permission.location.request().isGranted && ok;
    }
    return ok;
  }

  Future<bool> init() async {
    FlutterBluePlus.setLogLevel(LogLevel.warning);
    FlutterBluePlus.setOperationQueueMode(OperationQueueMode.perDevice);

    FlutterBluePlus.adapterState.listen((s) {
      if (s == BluetoothAdapterState.on && _device != null && !_intentionalStop) {
        _scheduleReconnect(Duration.zero);
      }
    });

    final saved = _getSavedId?.call();
    if (saved != null && saved.isNotEmpty) {
      status = 'Auto-connecting to saved scooter…';
      _intentionalStop = false;
      connectedId = saved;
      await _connectFlow(BluetoothDevice.fromId(saved), firstTry: false);
    }
    return true;
  }

  Future<void> scan() async {
    if (state == BmsState.scanning) return;
    await FlutterBluePlus.stopScan();
    state = BmsState.scanning;
    candidates = [];
    status = 'Scanning for scooter BMS…';
    notifyListeners();

    final results = <String, ScanCandidate>{};
    final sub = FlutterBluePlus.scanResults.listen((rs) {
      for (final r in rs) {
        final id = r.device.remoteId.str;
        if (results.containsKey(id)) continue;
        final name = r.device.platformName.isEmpty ? '(no name)' : r.device.platformName;
        final guess = guessFamily(
          r.advertisementData.serviceUuids,
          r.device.platformName,
        );
        if (guess == null) continue; // filter: only BMS-looking devices
        results[id] = ScanCandidate(
          id: id,
          name: name,
          guess: familyHint(guess),
          bonded: false,
        );
      }
      candidates = results.values.toList();
      notifyListeners();
    });

    try {
      await FlutterBluePlus.startScan(
        withServices: [
          Guid('0000ff00-0000-1000-8000-00805f9b34fb'),
          Guid('0000fff0-0000-1000-8000-00805f9b34fb'),
          Guid('0000ffe0-0000-1000-8000-00805f9b34fb'),
        ],
        timeout: const Duration(seconds: 8),
      );
    } catch (e) {
      status = 'Scan error: $e';
    } finally {
      await sub.cancel();
      await FlutterBluePlus.stopScan();
      if (state == BmsState.scanning) {
        state = BmsState.idle;
        if (candidates.isEmpty) status = 'No BMS found — turn scooter on and retry';
      }
      notifyListeners();
    }
  }

  Future<void> connectTo(ScanCandidate c) async {
    _intentionalStop = false;
    connectedId = c.id;
    connectedName = c.name;
    _setSavedId?.call(c.id);
    await _connectFlow(BluetoothDevice.fromId(c.id), firstTry: true);
  }

  Future<void> _connectFlow(BluetoothDevice device, {required bool firstTry}) async {
    if (_connecting) return;
    _connecting = true;
    state = BmsState.connecting;
    status = 'Connecting to ${connectedName ?? device.platformName}…';
    notifyListeners();
    _device = device;

    _stateSub ??= device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) {
        latest = null;
        proto?.dispose();
        proto = null;
        if (!_intentionalStop) {
          state = BmsState.idle;
          status = 'Disconnected — reconnecting…';
          notifyListeners();
          _scheduleReconnect(Duration(seconds: 1 << _retry.clamp(0, 5)));
        }
      }
    });

    var ok = false;
    try {
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 12),
        mtu: 247,
        autoConnect: false,
      );
      ok = true;
    } catch (e) {
      // Fallback: device may not have been seen this launch.
      if (firstTry) {
        final found = await _scanFor(device.remoteId.str);
        if (found != null) {
          try {
            await found.connect(
              license: License.nonprofit,
              timeout: const Duration(seconds: 12),
              mtu: 247,
            );
            ok = true;
          } catch (_) {}
        }
      }
      if (!ok) {
        _connecting = false;
        state = BmsState.error;
        status = firstTry ? 'Could not find scooter (power it on)' : 'Connection failed: $e';
        notifyListeners();
        return;
      }
    }

    _connecting = false;
    _retry = 0;
    if (ok) await _postConnect(device);
  }

  Future<BluetoothDevice?> _scanFor(String remoteId) async {
    await FlutterBluePlus.stopScan();
    BluetoothDevice? found;
    final sub = FlutterBluePlus.scanResults.listen((rs) {
      for (final r in rs) {
        if (r.device.remoteId.str == remoteId) found = r.device;
      }
    });
    await FlutterBluePlus.startScan(
      withRemoteIds: [remoteId],
      timeout: const Duration(seconds: 8),
    );
    await sub.cancel();
    await FlutterBluePlus.stopScan();
    return found;
  }

  Future<void> _postConnect(BluetoothDevice device) async {
    final services = await device.discoverServices();
    BluetoothService? svc;

    BluetoothService? pick(Guid g) {
      for (final s in services) {
        if (s.uuid.toString().toLowerCase() == g.toString().toLowerCase()) return s;
      }
      return null;
    }

    svc = pick(guidShort(0xff00)) ?? pick(guidShort(0xfff0)) ?? pick(guidShort(0xffe0));
    svc ??= services.cast<BluetoothService?>().firstWhere(
          (s) => s!.characteristics.any((c) => c.properties.notify),
          orElse: () => null,
        );
    if (svc == null) {
      status = 'No BMS GATT service found';
      state = BmsState.error;
      notifyListeners();
      await device.disconnect();
      return;
    }

    BluetoothCharacteristic? rx;
    BluetoothCharacteristic? tx;
    for (final c in svc.characteristics) {
      rx ??= c.properties.notify ? c : null;
      tx ??= (c.properties.write || c.properties.writeWithoutResponse) ? c : null;
    }
    if (rx == null || tx == null) {
      status = 'BMS service missing RX/TX characteristics';
      state = BmsState.error;
      notifyListeners();
      await device.disconnect();
      return;
    }
    final BluetoothCharacteristic writeChar = tx;

    final family = _detectFamily(services, device.platformName);
    proto = _buildProtocol(family);
    if (proto == null) {
      status = 'Unsupported BMS family ($family)';
      state = BmsState.error;
      notifyListeners();
      await device.disconnect();
      return;
    }

    proto!.send = (bytes) {
      try {
        writeChar.write(bytes, withoutResponse: true);
      } catch (_) {}
    };
    proto!.onTelemetry = (t) {
      latest = t;
      _telemetry.add(t);
      notifyListeners();
    };

    rx.onValueReceived.listen(proto!.feed);

    final ok = await proto!.init();
    if (!ok) {
      status = '${proto!.name} protocol not fully supported yet';
      state = BmsState.error;
      notifyListeners();
      await device.disconnect();
      return;
    }

    state = BmsState.connected;
    status = 'Connected · ${proto!.name}';
    notifyListeners();

    _pollTimer?.cancel();
    _cellTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      proto?.poll();
    });
    if (proto is JbdProtocol) {
      final jbd = proto as JbdProtocol;
      _cellTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        jbd.send(jbd.pollCells());
      });
    }
  }

  BmsFamily _detectFamily(List<BluetoothService> services, String name) {
    final ss = services.map((s) => s.uuid).toList();
    final guess = guessFamily(ss, name);
    if (guess != null) return guess;

    final hasff00 = ss.any((g) => g.toString().toLowerCase().contains('ff00'));
    final hasfff0 = ss.any((g) => g.toString().toLowerCase().contains('fff0'));
    final hasffe0 = ss.any((g) => g.toString().toLowerCase().contains('ffe0'));
    if (hasffe0) return BmsFamily.jk;
    if (hasff00) return BmsFamily.jbd;
    if (hasfff0) return BmsFamily.dalyA5;
    return BmsFamily.jbd;
  }

  BmsProtocol? _buildProtocol(BmsFamily f) => switch (f) {
        BmsFamily.jbd => JbdProtocol(),
        BmsFamily.dalyA5 => DalyA5Protocol(),
        BmsFamily.dalyModbus => DalyModbusProtocol(),
        BmsFamily.jk => JkProtocol(),
        BmsFamily.ant => AntProtocol(),
      };

  void _scheduleReconnect(Duration delay) {
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      final id = connectedId;
      if (id == null || _intentionalStop) return;
      _connectFlow(BluetoothDevice.fromId(id), firstTry: false);
    });
  }

  Future<void> disconnect() async {
    _intentionalStop = true;
    _pollTimer?.cancel();
    _cellTimer?.cancel();
    _retryTimer?.cancel();
    await _device?.disconnect();
    proto?.dispose();
    proto = null;
    latest = null;
    state = BmsState.idle;
    status = 'Disconnected';
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _cellTimer?.cancel();
    _retryTimer?.cancel();
    _telemetry.close();
    super.dispose();
  }
}
