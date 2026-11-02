import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'bms_manager.dart';
import 'models.dart';
import 'native_permissions.dart';
import 'range.dart';
import 'scan_log.dart';
import 'store.dart';

class ActiveRide {
  DateTime start = DateTime.now();
  double distanceM = 0;
  double lastLat = 0, lastLng = 0;
  bool hasFix = false;
  double whUsed = 0;
  double whRegen = 0;
  int socStart = 0;
  int socEnd = 0;
  double maxSpeed = 0;
  double avgSpeedKmh = 0;
  int stops = 0;
  bool wasMoving = false;
  final Map<RideMode, double> modeSeconds = {
    for (final m in RideMode.values) m: 0.0,
  };
  DateTime lastTick = DateTime.now();

  String get durationLabel {
    final d = DateTime.now().difference(start).inSeconds ~/ 60;
    final h = d ~/ 60;
    final m = d % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}

class AppController extends ChangeNotifier {
  final BmsManager bms = BmsManager();
  final AppStore store = AppStore();
  final ScanLogger scanLog = ScanLogger();
  late RangeEngine range;

  ActiveRide? ride;
  StreamSubscription<Position>? _gpsSub;
  Timer? _rideTimer;
  DiagnosticResult? lastDiagnostic;
  List<Trip> history = [];

  double gpsSpeedKmh = 0;

  AppController() {
    bms.attachStorage(
      getSavedId: () => store.savedDeviceId ?? '',
      setSavedId: (id) => store.setSavedDeviceId(id),
    );
  }

  Future<void> init() async {
    await store.init();
    await scanLog.init();
    bms.attachLogger(scanLog);
    final mass = store.scooterWeightKg + store.riderWeightKg;
    range = RangeEngine(
      estimator: RangeEstimator(massKg: mass),
      factors: store.factors,
      usableWh: store.usableWh,
    );
    await bms.init();
    await refreshHistory();
  }

  Future<void> refreshHistory() async {
    history = await store.rides();
    notifyListeners();
  }

  Future<void> requestPermissionsAndScan() async {
    final adapterOk = await bms.ensureAdapterOn();
    if (!adapterOk) return;
    final permOk = await bms.ensurePermissions();
    if (!permOk) return;
    await bms.scan();
  }

  double get currentSpeedKmh => gpsSpeedKmh;

  Future<void> startRide() async {
    if (ride != null) return;
    final t = bms.latest;
    if (t == null) return;

    // Location is only needed for ride tracking (GPS), not for BLE.
    final locOk = await NativePermissions.requestLocation();
    if (!locOk) {
      return; // user denied location; ride will not start
    }

    ride = ActiveRide()..socStart = t.socPercent;
    lastDiagnostic = null;
    await WakelockPlus.enable();

    _gpsSub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
        timeLimit: null,
      ),
    ).listen((pos) {
      final r = ride;
      if (r == null) return;
      if (r.hasFix) {
        final d = _haversine(r.lastLat, r.lastLng, pos.latitude, pos.longitude);
        r.distanceM += d;
      }
      r.lastLat = pos.latitude;
      r.lastLng = pos.longitude;
      r.hasFix = true;
      gpsSpeedKmh = pos.speed * 3.6;
      if (gpsSpeedKmh > r.maxSpeed) r.maxSpeed = gpsSpeedKmh;

      final moving = gpsSpeedKmh > 1.5;
      if (!moving && r.wasMoving) {
        // stop event: moving -> stationary
        r.stops++;
      }
      r.wasMoving = moving;
      notifyListeners();
    }, onError: (_) {});

    _rideTimer = Timer.periodic(const Duration(seconds: 1), (_) => _rideTick());
  }

  void _rideTick() {
    final r = ride;
    final t = bms.latest;
    if (r == null || t == null) return;

    final now = DateTime.now();
    final dt = now.difference(r.lastTick).inSeconds.toDouble();
    r.lastTick = now;

    // Energy integration: Wh = W * hours
    final dtH = dt / 3600.0;
    if (t.powerW > 0) {
      r.whUsed += t.powerW * dtH;
    } else {
      r.whRegen += -t.powerW * dtH;
    }
    final speed = currentSpeedKmh;
    final mode = modeForSpeed(speed);
    r.modeSeconds[mode] = (r.modeSeconds[mode] ?? 0) + dt;

    if (speed > 0) {
      r.avgSpeedKmh = r.distanceM / 1000.0 / (now.difference(r.start).inSeconds / 3600.0);
    }
    r.socEnd = t.socPercent;
    notifyListeners();
  }

  Future<void> stopRide() async {
    final r = ride;
    if (r == null) return;
    await _gpsSub?.cancel();
    _gpsSub = null;
    _rideTimer?.cancel();
    _rideTimer = null;
    await WakelockPlus.disable();

    final durationS = DateTime.now().difference(r.start).inSeconds.toDouble();
    final distKm = r.distanceM / 1000.0;
    final whPerKm = distKm > 0.05 ? r.whUsed / distKm : 0.0;

    // Dominant mode by seconds
    RideMode dom = RideMode.eco;
    var best = -1.0;
    r.modeSeconds.forEach((k, v) {
      if (v > best) {
        best = v;
        dom = k;
      }
    });

    final trip = Trip(
      start: r.start,
      end: DateTime.now(),
      distanceM: r.distanceM,
      durationS: durationS,
      whUsed: r.whUsed,
      whRegen: r.whRegen,
      whPerKm: whPerKm,
      avgSpeedKmh: distKm > 0 ? distKm / (durationS / 3600.0) : 0,
      maxSpeedKmh: r.maxSpeed,
      socStart: r.socStart,
      socEnd: r.socEnd,
      protocol: bms.proto?.name ?? '?',
      stops: r.stops,
      modeSeconds: r.modeSeconds.map((k, v) => MapEntry(modeName(k), v)),
    );

    if (distKm > 0.05 && whPerKm > 0) {
      // update rider factor
      final stopsPerKm = distKm > 0 ? r.stops / distKm : 0.0;
      final expected = range.estimator.whPerKmTrip(
            avgSpeedKmh: trip.avgSpeedKmh,
            mode: dom,
            stopsPerKm: stopsPerKm,
          );
      final ratio = whPerKm / expected;
      range.factors = range.factors.updated(dom, ratio);
      await store.saveFactors(range.factors);

      lastDiagnostic = range.diagnoseTrip(
        whPerKmMeasured: whPerKm,
        mode: dom,
        stopsPerKm: stopsPerKm,
        avgSpeedKmh: trip.avgSpeedKmh,
      );
    }

    await store.insertTrip(trip);
    await refreshHistory();
    ride = null;
    gpsSpeedKmh = 0;
    notifyListeners();
  }

  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;

  @override
  void dispose() {
    _gpsSub?.cancel();
    _rideTimer?.cancel();
    bms.dispose();
    super.dispose();
  }
}
