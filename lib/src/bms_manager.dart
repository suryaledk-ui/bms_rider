import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'models.dart';
import 'native_legacy_scan.dart';
import 'native_location_services.dart';
import 'native_permissions.dart';
import 'protocol.dart';
import 'protocol_daly.dart';
import 'protocol_jbd.dart';
import 'protocol_jk.dart';
import 'scan_log.dart';

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

  ScanLogger? _log;
  void attachLogger(ScanLogger log) => _log = log;
  void _lg(String tag, String msg) => _log?.log(tag, msg);

  void attachStorage({required String Function() getSavedId, required void Function(String) setSavedId}) {
    _getSavedId = getSavedId;
    _setSavedId = setSavedId;
  }

  Future<bool> ensureAdapterOn() async {
    _lg('BT', 'adapter state at check: ${FlutterBluePlus.adapterStateNow}');
    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) return true;
    try {
      await FlutterBluePlus.turnOn();
    } catch (e) {
      _lg('BT', 'turnOn() threw: $e');
    }
    // Poll the actual state for up to 5s instead of trusting turnOn() alone.
    for (var i = 0; i < 25; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) {
        _lg('BT', 'adapter now ON');
        return true;
      }
    }
    _lg('BT', 'adapter failed to turn on (state=${FlutterBluePlus.adapterStateNow})');
    return false;
  }

  Future<bool> ensurePermissions() async {
    return NativePermissions.requestBleOnly();
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
      _lg('BOOT', 'auto-connect saved device $saved');
      _intentionalStop = false;
      connectedId = saved;
      await _connectFlow(BluetoothDevice.fromId(saved), firstTry: false);
    }
    return true;
  }

  Future<void> scan() async {
    // Synchronous guard (set before any await) so parallel triggers
    // (auto-scan + manual button) cannot start two overlapping scans.
    if (_scanInFlight) {
      _lg('SCAN', 'scan() ignored — scan already in flight');
      return;
    }
    _scanInFlight = true;

    try {
      await _scanInternal();
    } finally {
      _scanInFlight = false;
    }
  }

  bool _scanInFlight = false;

  Future<void> _scanInternal() async {
    await FlutterBluePlus.stopScan();

    // Preflight 1: adapter must actually be ON.
    final adapterOn = await ensureAdapterOn();
    debugPrint('[SCANDBG] adapterOn=$adapterOn state=${FlutterBluePlus.adapterStateNow}');
    if (!adapterOn) {
      state = BmsState.error;
      status = 'Bluetooth is OFF — turn it on (Quick Settings) and try again';
      _lg('SCAN', 'aborted: adapter not on');
      notifyListeners();
      return;
    }

    // Preflight 2: permissions must actually be granted.
    final permOk = await ensurePermissions();
    debugPrint('[SCANDBG] permissionsOk=$permOk');
    if (!permOk) {
      state = BmsState.error;
      status = 'Bluetooth permission denied — allow it in Settings and try again';
      _lg('SCAN', 'aborted: permissions missing/denied');
      notifyListeners();
      return;
    }

    // Preflight 3: Android silently drops ALL scan results while the system
    // Location Services (GPS master switch) is OFF — BLE scanning is treated
    // as location-derived because we don't declare neverForLocation.
    if (kIsWeb == false && defaultTargetPlatform == TargetPlatform.android) {
      final locationOn = await NativeLocationServices.isEnabled();
      debugPrint('[SCANDBG] locationServicesOn=$locationOn');
      if (!locationOn) {
        state = BmsState.error;
        status = 'Location Services are OFF — enable GPS Location in Quick Settings, then scan again';
        _lg('SCAN', 'aborted: location services off');
        notifyListeners();
        return;
      }
    }

    // Small settle delay after granting permissions: the very first scan on
    // several Android phones (Samsung/realme) returns empty if started too
    // quickly after the permission dialog closes.
    await Future<void>.delayed(const Duration(milliseconds: 400));

    state = BmsState.scanning;
    candidates = [];
    status = 'Scanning for nearby BLE devices…';
    _lg('SCAN', 'scan started (all devices, no filters) adapter=${FlutterBluePlus.adapterStateNow}');
    debugPrint('[SCANDBG] starting scan isScanningNow=${FlutterBluePlus.isScanningNow}');
    notifyListeners();

    // Phase 1: NATIVE LEGACY scan (BluetoothAdapter.startLeScan) — the exact
    // API BAT-BMS/FastBLE uses, which works on cheap Android 12 stacks where
    // the new BluetoothLeScanner silently returns nothing.
    // Phase 2 (if still zero): flutter_blue_plus scan fallback.
    final first = await _runNativeLegacyScan();
    if (first.isEmpty) {
      _lg('SCAN', 'legacy scan empty — retrying with FBP scan');
      debugPrint('[SCANDBG] legacy scan empty → FBP scan');
      candidates = await _runFbpScan();
    } else {
      candidates = first;
    }

    state = BmsState.idle;
    if (candidates.isEmpty) {
      status = 'No BLE devices found — turn scooter on and retry';
      _lg('SCAN', 'finished: 0 devices seen (both phases)');
    } else {
      status = '${candidates.length} device(s) found';
      _lg('SCAN', 'finished: ${candidates.length} devices seen');
    }
    notifyListeners();
  }

  Future<List<ScanCandidate>> _runNativeLegacyScan() async {
    final started = DateTime.now();
    final raw = await NativeLegacyScan.scan(const Duration(seconds: 8));
    final elapsed = DateTime.now().difference(started).inMilliseconds;
    debugPrint('[SCANDBG] native legacy scan done in ${elapsed}ms results=${raw.length}');

    final results = <String, ScanCandidate>{};
    for (final r in raw) {
      if (r.id.isEmpty) continue;
      final guess = guessFamily(const [], r.name);
      // Skip nameless non-BMS noise (no name).
      if (guess == null && r.name.isEmpty) continue;
      results[r.id] = ScanCandidate(
        id: r.id,
        name: r.name.isEmpty ? '(no name)' : r.name,
        guess: guess == null ? 'Unknown' : familyHint(guess),
        rssi: r.rssi,
        bonded: false,
      );
      debugPrint('[SCANDBG] [legacy] seen ${r.id} name="${r.name.isEmpty ? '(none)' : r.name}" '
          'rssi=${r.rssi} family=${guess == null ? 'unknown' : familyHint(guess)}');
    }
    final list = results.values.toList();
    list.sort((a, b) {
      final aKnown = a.guess != 'Unknown' ? 0 : 1;
      final bKnown = b.guess != 'Unknown' ? 0 : 1;
      if (aKnown != bKnown) return aKnown - bKnown;
      return b.rssi.compareTo(a.rssi);
    });
    return list.take(50).toList();
  }

  Future<List<ScanCandidate>> _runFbpScan() async {
    final results = <String, ScanCandidate>{};
    final sub = FlutterBluePlus.scanResults.listen((rs) {
      for (final r in rs) {
        final id = r.device.remoteId.str;
        final name = r.device.platformName.isEmpty ? '' : r.device.platformName;
        final guess = guessFamily(r.advertisementData.serviceUuids, name);
        if (results.containsKey(id)) {
          final old = results[id]!;
          results[id] = ScanCandidate(
            id: id,
            name: name.isEmpty ? old.name : name,
            guess: guess == null ? old.guess : familyHint(guess).toString(),
            rssi: r.rssi,
            bonded: old.bonded,
          );
          continue;
        }
        // Skip nameless non-BMS noise (no name, no known service).
        if (guess == null && name.isEmpty) continue;
        results[id] = ScanCandidate(
          id: id,
          name: name.isEmpty ? '(no name)' : name,
          guess: guess == null ? 'Unknown' : familyHint(guess).toString(),
          rssi: r.rssi,
          bonded: false,
        );
        debugPrint('[SCANDBG] [fbp] seen $id name="${name.isEmpty ? '(none)' : name}" '
            'svcs=${r.advertisementData.serviceUuids.map((g) => g.toString()).join(',')} '
            'rssi=${r.rssi} family=${guess == null ? 'unknown' : familyHint(guess)}');
      }
    });

    try {
      await FlutterBluePlus.startScan(
        androidCheckLocationServices: false,
        androidLegacy: true,
        androidUsesFineLocation: true,
        timeout: const Duration(seconds: 8),
      );
      debugPrint('[SCANDBG] FBP scan returned results=${results.length}');
    } catch (e) {
      debugPrint('[SCANDBG] FBP scan threw: $e');
      _lg('SCAN', 'FBP scan threw: $e');
    } finally {
      await sub.cancel();
      await FlutterBluePlus.stopScan();
    }

    final list = results.values.toList();
    list.sort((a, b) {
      final aKnown = a.guess != 'Unknown' ? 0 : 1;
      final bKnown = b.guess != 'Unknown' ? 0 : 1;
      if (aKnown != bKnown) return aKnown - bKnown;
      return b.rssi.compareTo(a.rssi);
    });
    return list.take(50).toList();
  }

  Future<void> connectTo(ScanCandidate c) async {
    _intentionalStop = false;
    connectedId = c.id;
    connectedName = c.name;
    _setSavedId?.call(c.id);
    _lg('CONN', 'user selected ${c.id} name="${c.name}" guess=${c.guess} rssi=${c.rssi}');
    await _connectFlow(BluetoothDevice.fromId(c.id), firstTry: true);
  }

  Future<void> _connectFlow(BluetoothDevice device, {required bool firstTry}) async {
    if (_connecting) return;
    _connecting = true;
    state = BmsState.connecting;
    status = 'Connecting to ${connectedName ?? device.platformName}…';
    _lg('CONN', 'attempt to ${device.remoteId.str} name="${connectedName ?? device.platformName}" firstTry=$firstTry');
    notifyListeners();
    _device = device;

    _stateSub ??= device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) {
        _lg('CONN', 'disconnected from ${device.remoteId.str} (intentional=$_intentionalStop)');
        latest = null;
        proto?.dispose();
        proto = null;
        if (!_intentionalStop) {
          state = BmsState.idle;
          status = 'Disconnected — reconnecting…';
          notifyListeners();
          final backoff = _retry > 3
              ? const Duration(seconds: 8)
              : Duration(seconds: 1 << _retry.clamp(0, 3));
          _scheduleReconnect(backoff);
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
        _lg('CONN', 'connect failed firstTry=$firstTry err=$e');
        notifyListeners();
        return;
      }
    }

    _connecting = false;
    _retry = 0;
    _lg('CONN', 'GATT connected to ${device.remoteId.str}');
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
      _lg('CONN', 'no BMS GATT service found on ${device.remoteId.str}');
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
      _lg('CONN', 'missing RX/TX characteristics on ${device.remoteId.str}');
      state = BmsState.error;
      notifyListeners();
      await device.disconnect();
      return;
    }
    final BluetoothCharacteristic writeChar = tx;
    // Some BMS modules (e.g. JBD clones) expose the TX characteristic as
    // write-without-response only. Writing "with response" to those fails
    // silently on Android, so no frames ever reach the BMS. Match the
    // characteristic's actual properties.
    final writeWithoutResponse =
        writeChar.properties.writeWithoutResponse && !writeChar.properties.write;

    final family = _detectFamily(services, device.platformName);
    _lg('CONN', 'protocol family detected: $family for ${device.remoteId.str}');
    proto = _buildProtocol(family);
    if (proto == null) {
      status = 'Unsupported BMS family ($family)';
      _lg('CONN', 'unsupported family $family');
      state = BmsState.error;
      notifyListeners();
      await device.disconnect();
      return;
    }

    proto!.send = (bytes) {
      try {
        if (writeWithoutResponse) {
          writeChar.write(bytes, withoutResponse: true);
        } else {
          writeChar.write(bytes);
        }
      } catch (e) {
        _lg('CONN', 'write failed (withoutResponse=$writeWithoutResponse): $e');
      }
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
      _lg('CONN', '${proto!.name} init returned false');
      state = BmsState.error;
      notifyListeners();
      await device.disconnect();
      return;
    }

    state = BmsState.connected;
    status = 'Connected · ${proto!.name}';
    _lg('CONN', 'connected OK: ${proto!.name} on ${device.remoteId.str}');
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
    // Fight harder: retry quickly, and keep retrying while the ride/device
    // is expected, with a cap so we never spin forever.
    final capped = delay > const Duration(seconds: 20) ? const Duration(seconds: 20) : delay;
    _retryTimer = Timer(capped, () {
      final id = connectedId;
      if (id == null || _intentionalStop) return;
      _retry++;
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
