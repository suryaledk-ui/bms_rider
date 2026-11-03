import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'bms_manager.dart';
import 'ml_range.dart';
import 'models.dart';
import 'native_permissions.dart';
import 'native_notifications.dart';
import 'range.dart';
import 'scan_log.dart';
import 'store.dart';
import 'weather.dart';

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
  late final RangeMl ml;

  ActiveRide? ride;
  StreamSubscription<Position>? _gpsSub;
  Timer? _rideTimer;
  DiagnosticResult? lastDiagnostic;
  List<Trip> history = [];

  WeatherInfo? weather;
  bool _weatherFetched = false;
  double gpsSpeedKmh = 0;
  double gpsHeadingDeg = 0;

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
    bms.telemetry.listen(_onTelemetry);
    final mass = store.scooterWeightKg + store.riderWeightKg;
    final estimator = RangeEstimator(massKg: mass);
    range = RangeEngine(
      estimator: estimator,
      factors: store.factors,
      usableWh: store.usableWh,
    );
    ml = RangeMl(estimator: estimator, state: store.mlState);
    await bms.init();
    await refreshHistory();

    // Auto-scan shortly after launch when no scooter is saved yet — makes
    // first-run discovery instant, and doubles as a self-test on connect.
    if (store.savedDeviceId == null || store.savedDeviceId!.isEmpty) {
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (!_autoScanFired) {
          _autoScanFired = true;
          requestPermissionsAndScan();
        }
      });
    }
  }

  bool _autoScanFired = false;

  Future<void> refreshHistory() async {
    history = await store.rides();
    notifyListeners();
  }

  bool _autoWhDone = false;

  // ---- charging state + phone notifications ----
  bool _wasCharging = false;
  bool _fullChargeNotified = false;
  double? _chargeEnergyWs; // energy poured while charging (current < 0)
  DateTime? _chargeStartedAt;

  /// True when the BMS reports it is charging right now.
  bool get isCharging => _wasCharging;

  /// Estimated minutes remaining to full charge, when charging.
  int? get chargeEtaMinutes {
    if (!_wasCharging || _chargeEnergyWs == null || _chargeStartedAt == null) {
      return null;
    }
    final elapsedMin = DateTime.now().difference(_chargeStartedAt!).inSeconds / 60.0;
    if (elapsedMin < 1.5) return null;
    final avgRateWhPerMin =
        (_chargeEnergyWs! / 3600.0) / elapsedMin;
    if (avgRateWhPerMin <= 0) return null;
    final soc = bms.latest?.socPercent;
    if (soc == null) return null;
    final missingWh = store.usableWh * (100 - soc) / 100.0;
    return (missingWh / avgRateWhPerMin).ceil();
  }

  // ---- automatic true-capacity estimation (coulomb count) ----
  double? _socAnchor;
  double? _dischargeEnergyWs;
  double? _estimatedCapacityWh;
  DateTime? _capacityEstimatedAt;

  /// Auto-estimated usable capacity (Wh) from measured discharge, nullable.
  double? get estimatedCapacityWh => _estimatedCapacityWh;
  DateTime? get capacityEstimatedAt => _capacityEstimatedAt;

  /// BMS reports nominal Ah + cell count — derive usable Wh automatically
  /// (unless the user set it manually): nominal Ah × cells × 3.70 V × 0.92.
  void _onTelemetry(Telemetry t) {
    if (_autoWhDone || store.usableWhManual) return;
    if (t.nominalAh > 0 && t.cellVolts.length >= 4) {
      final derivedWh = t.nominalAh * t.cellVolts.length * 3.70 * 0.92;
      if (derivedWh > 200 && derivedWh < 6000) {
        _autoWhDone = true;
        store.setUsableWh(derivedWh);
        final mass = store.scooterWeightKg + store.riderWeightKg;
        range = RangeEngine(
          estimator: RangeEstimator(massKg: mass),
          factors: store.factors,
          usableWh: derivedWh,
        );
        scanLog.log('BMS', 'auto-derived usableWh=${derivedWh.toStringAsFixed(0)} '
            '(nom ${t.nominalAh.toStringAsFixed(2)}Ah × ${t.cellVolts.length} cells)');
        notifyListeners();
      }
    }

    // Charging lifecycle + notifications.
    //
    // On several JBD clones the charging flag bit is unreliable and the
    // current sign is inverted while discharging. Use current MAGNITUDE as
    // the primary signal: strong inflow (>1A) means charging; medium inflow
    // only counts as charging when the flag also agrees.
    final charging = t.currentA < -1.0 || (t.charging && t.currentA < -0.3);
    if (charging) {
      if (!_wasCharging) {
        _wasCharging = true;
        _fullChargeNotified = false;
        _chargeEnergyWs = 0;
        _chargeStartedAt = DateTime.now();
      } else {
        // integrate charger power (current negative = into battery)
        _chargeEnergyWs = (_chargeEnergyWs ?? 0) + (t.powerW.abs() * 2.0);
      }
      if (t.socPercent >= 99 && !_fullChargeNotified) {
        _fullChargeNotified = true;
        _maybeNotify(
          'Battery full',
          'Your scooter is fully charged (${t.socPercent}%). Unplug when convenient.',
        );
      }
    } else if (_wasCharging) {
      _wasCharging = false;
      _chargeEnergyWs = null;
      _chargeStartedAt = null;
    }

    // Coulomb-count auto capacity: track WH drawn while discharging and the
    // SOC delta across that window; when ΔSOC ≥ 10% we can estimate usable
    // capacity = energyUsed / (ΔSOC/100).
    //
    // Sign normalization: power > 0 = discharge on standard boards; on the
    // inverted-sign clones the same physical discharge shows as power < 0
    // while NOT charging — treat that magnitude as discharge too.
    final dischargeW = t.powerW > 0
        ? t.powerW
        : (!charging && t.currentA < -0.2 ? -t.powerW : 0.0);
    if (dischargeW > 0.5) {
      _dischargeEnergyWs = (_dischargeEnergyWs ?? 0) + (dischargeW * 2.0);
      _socAnchor ??= t.socPercent.toDouble();
      final delta = _socAnchor! - t.socPercent;
      final used = (_dischargeEnergyWs! / 3600.0);
      if (delta >= 10 && used > 15) {
        final est = used / (delta / 100.0);
        if (est > 200 && est < 8000) {
          final improved = _estimatedCapacityWh == null ||
              (est - _estimatedCapacityWh!).abs() / _estimatedCapacityWh! > 0.05;
          if (improved) {
            _estimatedCapacityWh = est;
            _capacityEstimatedAt = DateTime.now();
            store.setCalibratedSoH(
              ((est / (store.usableWh == 0 ? 1 : store.usableWh) * 100)
                      .clamp(20, 120))
                  .toDouble(),
            );
            scanLog.log('BMS', 'auto capacity estimate ≈${est.toStringAsFixed(0)}Wh '
                '(ΔSOC $delta%, ${used.toStringAsFixed(1)}Wh used)');
          }
        }
        _socAnchor = t.socPercent.toDouble();
        _dischargeEnergyWs = 0;
      }
    } else {
      _socAnchor = t.socPercent.toDouble();
      _dischargeEnergyWs = 0;
    }
  }

  /// Apply rider/scooter/tyre/capacity profile changes live.
  Future<void> updateProfile({
    double? riderWeightKg,
    double? scooterWeightKg,
    double? tirePressurePsi,
    double? usableWh,
    VehiclePreset? preset,
  }) async {
    if (preset != null) {
      await store.setVehiclePresetId(preset.id);
      await store.setScooterWeightKg(preset.scooterKg);
      await store.setUsableWh(preset.usableWh);
      await store.setTirePressurePsi(preset.ratedPhi);
      await store.setTirePressureCheckedAt(DateTime.now());
    } else {
      if (riderWeightKg != null) await store.setRiderWeightKg(riderWeightKg);
      if (scooterWeightKg != null) await store.setScooterWeightKg(scooterWeightKg);
      if (tirePressurePsi != null) {
        await store.setTirePressurePsi(tirePressurePsi);
        await store.setTirePressureCheckedAt(DateTime.now());
      }
      if (usableWh != null) await store.setUsableWh(usableWh);
    }
    final mass = store.scooterWeightKg + store.riderWeightKg;
    range = RangeEngine(
      estimator: RangeEstimator(massKg: mass),
      factors: store.factors,
      usableWh: store.usableWh,
    );
    notifyListeners();
  }

  Future<void> requestPermissionsAndScan() async {
    await bms.scan();
  }

  void _maybeNotify(String title, String body) {
    NativeNotifications.show(title, body);
    scanLog.log('NOTIFY', '$title — $body');
  }

  double get currentSpeedKmh => gpsSpeedKmh;

  /// Speed used for display + live range: EMA-smoothed version of the raw
  /// GPS speed, so the UI doesn't jump around (GPS is noisy/jittery).
  double _smoothedSpeedKmh = 0;
  double get smoothedSpeedKmh => _smoothedSpeedKmh;

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
      gpsHeadingDeg = pos.heading;
      // EMA smoothing: fast enough to feel instant, slow enough to hide
      // GPS jitter (alpha ~0.25 → settle in ~2–3 updates).
      _smoothedSpeedKmh += (gpsSpeedKmh - _smoothedSpeedKmh) * 0.25;
      if (gpsSpeedKmh > r.maxSpeed) r.maxSpeed = gpsSpeedKmh;

      // Fetch ambient weather once per ride (temp/wind for range accuracy).
      if (!_weatherFetched) {
        _weatherFetched = true;
        fetchWeather(pos.latitude, pos.longitude).then((w) {
          if (w != null) {
            weather = w;
            notifyListeners();
          }
        });
      }

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

    // Energy integration: Wh = W * hours.
    //
    // Sign normalization: on inverted-sign JBD clones, physical discharge
    // shows as negative current. Distinguish by charging state — when not
    // charging, negative power magnitude is discharge, not regen.
    final dtH = dt / 3600.0;
    final charging = t.currentA < -1.0 || (t.charging && t.currentA < -0.3);
    final dischargeW = t.powerW > 0
        ? t.powerW
        : (!charging && t.currentA < -0.2 ? -t.powerW : 0.0);
    if (dischargeW > 0.5) {
      r.whUsed += dischargeW * dtH;
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

    // Energy accounting.
    //
    // Some JBD clones report discharge current with INVERTED sign (we saw
    // wh_used stay 0.0 while wh_regen grew on every ride, even though SOC
    // was falling). Guard: if the raw watt-integral is implausibly low but
    // the SOC dropped by >= 1%, fall back to a SOC-based energy estimate.
    var whUsed = r.whUsed;
    final socDelta = (r.socStart - r.socEnd).toDouble();
    if (whUsed < 2.0 && socDelta >= 1.0) {
      final socBased = store.usableWh * (socDelta / 100.0);
      if (socBased > whUsed) {
        scanLog.log('BMS', 'current sign fallback: raw ${whUsed.toStringAsFixed(1)}Wh '
            '→ SOC-based ${socBased.toStringAsFixed(1)}Wh (ΔSOC $socDelta%)');
        whUsed = socBased;
      }
    }
    final whPerKm = distKm > 0.05 ? whUsed / distKm : 0.0;

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
      whUsed: whUsed,
      whRegen: r.whRegen,
      whPerKm: whPerKm,
      avgSpeedKmh: distKm > 0 ? distKm / (durationS / 3600.0) : 0,
      maxSpeedKmh: r.maxSpeed,
      socStart: r.socStart,
      socEnd: r.socEnd,
      protocol: bms.proto?.name ?? '?',
      stops: r.stops,
      modeSeconds: r.modeSeconds.map((k, v) => MapEntry(modeName(k), v)),
      // Snapshot the weight used for THIS ride so future calibrations stay
      // correct even if the user later changes the profile.
      riderKg: store.riderWeightKg,
      scooterKg: store.scooterWeightKg,
    );

    if (distKm > 0.05 && whPerKm > 0) {
      // update rider factor, using the trip's own weight snapshot
      final stopsPerKm = distKm > 0 ? r.stops / distKm : 0.0;
      final massKg =
          (trip.riderKg + trip.scooterKg) > 0
              ? trip.riderKg + trip.scooterKg
              : store.scooterWeightKg + store.riderWeightKg;
      final estimator = RangeEstimator(massKg: massKg);
      final expected = estimator.whPerKmTrip(
            avgSpeedKmh: trip.avgSpeedKmh,
            mode: dom,
            stopsPerKm: stopsPerKm,
            tirePsi: store.tirePressurePsi,
            weather: weather,
          );
      final ratio = whPerKm / expected;
      range.factors = range.factors.updated(dom, ratio);
      await store.saveFactors(range.factors);
      scanLog.log('BMS', 'calibration: ${whPerKm.toStringAsFixed(1)}Wh/km vs '
          'expected ${expected.toStringAsFixed(1)} (${modeName(dom)}, '
          '${massKg.toStringAsFixed(0)}kg) → factor ${ratio.toStringAsFixed(2)}');

      final lastCheck = store.tirePressureCheckedAt;
      final daysSinceCheck = lastCheck == null
          ? 999
          : DateTime.now().difference(lastCheck).inDays;

      lastDiagnostic = range.diagnoseTrip(
        whPerKmMeasured: whPerKm,
        mode: dom,
        stopsPerKm: stopsPerKm,
        avgSpeedKmh: trip.avgSpeedKmh,
        weather: weather,
        tirePsi: store.tirePressurePsi,
        daysSinceTyreCheck: daysSinceCheck,
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
