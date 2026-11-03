import 'dart:math' as math;

import 'package:bms_rider/src/ml_range.dart';
import 'package:bms_rider/src/models.dart';
import 'package:bms_rider/src/range.dart';
import 'package:flutter_test/flutter_test.dart';

/// Faithful copy of the model's offline posterior + Welford state, so tests
/// can compute the closed-form ridge solution independently of the model
/// (same equations: Λ ← γΛ + xxᵀ/σ², b ← γb + xy/σ², μ = Λ⁻¹b).
class _RidgeReplica {
  static const int kFeatures = 6;
  static const double kappa = 2.0; // prior precision scalar
  static const double sigma2 = 9.0; // measurement noise (Wh/km)²
  static const double gamma = 0.985; // forgetting factor

  final RideMode mode;
  final RangeEstimator est;

  final List<double> mu = List.filled(kFeatures, 0);
  final List<List<double>> L =
      List.generate(kFeatures, (_) => List.filled(kFeatures, 0));
  final List<double> b = List.filled(kFeatures, 0);
  double n = 0;

  final List<double> featMean = List.filled(kFeatures, 0);
  final List<double> featM2 = List.filled(kFeatures, 0);
  final List<double> featCount = List.filled(kFeatures, 10);
  List<double> lastX = List.filled(kFeatures, 0);

  _RidgeReplica(this.mode, this.est) {
    for (var i = 0; i < kFeatures; i++) {
      L[i][i] = kappa;
    }
    final refSpeed = RangeEstimator.refSpeed(mode);
    final physics = est.whPerKmAt(refSpeed, mode, tirePsi: 32, headwindKmh: 0);
    mu[0] = physics / 0.5;
    for (var i = 0; i < kFeatures; i++) {
      b[i] = kappa * mu[i];
    }
    const means = [0.0, 1.0, 140.0, 32.0, 22.0, 5.0];
    const stds = [10.0, 1.0, 25.0, 6.0, 10.0, 8.0];
    for (var i = 0; i < kFeatures; i++) {
      featMean[i] = means[i];
      featM2[i] = 10.0 * stds[i] * stds[i];
    }
    featMean[0] = refSpeed - 5;
  }

  double _std(int i) {
    final k = featCount[i];
    if (k < 2) return 1.0;
    final variance = featM2[i] / k;
    return variance < 1e-6 ? 1.0 : math.sqrt(variance);
  }

  void update(
    double speed,
    double stops,
    double mass,
    double psi,
    double? temp,
    double? wind,
    double y,
  ) {
    final raw = <double>[speed, stops, mass, psi, temp ?? 0, wind ?? 0];
    for (var i = 0; i < kFeatures; i++) {
      final v = raw[i];
      final k = featCount[i] + 1;
      final delta = v - featMean[i];
      featMean[i] += delta / k;
      featM2[i] += delta * (v - featMean[i]);
      featCount[i] = k;
      lastX[i] = (v - featMean[i]) / _std(i);
    }
    if (n > 0) {
      for (var i = 0; i < kFeatures; i++) {
        b[i] *= gamma;
        for (var j = 0; j < kFeatures; j++) {
          L[i][j] *= gamma;
        }
      }
      n *= gamma;
    }
    final invSigma2 = 1 / sigma2;
    for (var i = 0; i < kFeatures; i++) {
      b[i] += lastX[i] * y * invSigma2;
      for (var j = 0; j < kFeatures; j++) {
        L[i][j] += lastX[i] * lastX[j] * invSigma2;
      }
    }
    n += 1;
    final solved = _solve(L, b);
    for (var i = 0; i < kFeatures; i++) {
      mu[i] = solved[i];
    }
  }

  static List<double> _solve(List<List<double>> a, List<double> x) {
    final nRows = a.length;
    final m = <List<double>>[
      for (var i = 0; i < nRows; i++) [...a[i], x[i]],
    ];
    for (var col = 0; col < nRows; col++) {
      var pivot = col;
      for (var r = col + 1; r < nRows; r++) {
        if (m[r][col].abs() > m[pivot][col].abs()) pivot = r;
      }
      if (m[pivot][col].abs() < 1e-12) continue;
      if (pivot != col) {
        final tmp = m[col];
        m[col] = m[pivot];
        m[pivot] = tmp;
      }
      final pv = m[col][col];
      for (var c = col; c <= nRows; c++) {
        m[col][c] /= pv;
      }
      for (var r = 0; r < nRows; r++) {
        if (r == col) continue;
        final f = m[r][col];
        if (f == 0) continue;
        for (var c = col; c <= nRows; c++) {
          m[r][c] -= f * m[col][c];
        }
      }
    }
    return [for (var i = 0; i < nRows; i++) m[i][nRows]];
  }

  double dot(List<double> other) {
    var acc = 0.0;
    for (var i = 0; i < kFeatures; i++) {
      acc += mu[i] * other[i];
    }
    return acc;
  }
}

RangeEstimator _est() => RangeEstimator(massKg: 100, cdA: 0.48, crrBase: 0.018);

/// Three distinct ride patterns (speed, stops, psi, temp, wind, whPerKm).
const List<(double, double, double, double, double, double)> _patterns = [
  (18.0, 0.5, 30.0, 18.0, 3.0, 30.0),
  (26.0, 2.5, 33.0, 11.0, 10.0, 38.0),
  (35.0, 1.8, 29.0, 27.0, 0.0, 45.0),
];

void _applyUpdates(RangeMl ml, int count, {double? temp, double? wind}) {
  for (var k = 0; k < count; k++) {
    final p = _patterns[k % _patterns.length];
    ml.update(
      RideMode.eco,
      speedKmh: p.$1,
      stopsPerKm: p.$2,
      massKg: 100,
      tirePsi: p.$3,
      tempC: temp,
      headwindKmh: wind,
      whPerKm: p.$6,
    );
  }
}

/// Expected blended prediction from closed-form posterior: (1−β)·physics + β·μᵀx.
double _expectedBlend(
  _RidgeReplica rep,
  double speed,
  double stops,
  double mass,
  double psi,
  double temp,
  double wind,
) {
  final physics = rep.est.whPerKmAt(
    speed,
    rep.mode,
    tirePsi: psi,
    headwindKmh: wind,
  );
  final beta = rep.n / (rep.n + 5.0);
  return (1 - beta) * physics + beta * rep.dot(rep.lastX);
}

/// Deep numerical comparison of two serialized states (within 1e-9).
void _expectDeepEqual(Object? a, Object? b) {
  if (a is Map && b is Map) {
    expect(a.keys.toSet(), b.keys.toSet());
    for (final k in a.keys) {
      _expectDeepEqual(a[k], b[k]);
    }
    return;
  }
  if (a is List && b is List) {
    expect(a.length, b.length);
    for (var i = 0; i < a.length; i++) {
      _expectDeepEqual(a[i], b[i]);
    }
    return;
  }
  final av = (a as num).toDouble();
  final bv = (b as num).toDouble();
  expect((av - bv).abs(), lessThanOrEqualTo(1e-9));
}

void _expectFiniteJson(Object? v) {
  if (v is Map) {
    v.values.forEach(_expectFiniteJson);
    return;
  }
  if (v is List) {
    v.forEach(_expectFiniteJson);
    return;
  }
  final d = (v as num).toDouble();
  expect(d.isFinite, isTrue);
}

/// Build state JSON with an exact `n` (restore semantics like `store.mlState`).
Map<String, dynamic> _stateWithN(RangeMl seed, double n) {
  final json = seed.toJson();
  (json['Eco'] as Map<String, dynamic>)['n'] = n;
  return json;
}

void main() {
  group('RangeMl', () {
    test('closed-form: online posterior matches batch ridge solution', () {
      final est = _est();
      final ml = RangeMl(estimator: est);
      final rep = _RidgeReplica(RideMode.eco, est);
      const updates = 90;
      for (var k = 0; k < updates; k++) {
        final p = _patterns[k % _patterns.length];
        ml.update(
          RideMode.eco,
          speedKmh: p.$1,
          stopsPerKm: p.$2,
          massKg: 100,
          tirePsi: p.$3,
          tempC: p.$4,
          headwindKmh: p.$5,
          whPerKm: p.$6,
        );
        rep.update(p.$1, p.$2, 100, p.$3, p.$4, p.$5, p.$6);
      }
      final p = _patterns[(updates - 1) % _patterns.length];
      final expected = _expectedBlend(rep, p.$1, p.$2, 100, p.$3, p.$4, p.$5);
      final actual = ml.predict(
        RideMode.eco,
        speedKmh: p.$1,
        stopsPerKm: p.$2,
        massKg: 100,
        tirePsi: p.$3,
        tempC: p.$4,
        headwindKmh: p.$5,
      );
      expect(actual, closeTo(expected, 1e-6));
      expect(ml.rideCount(RideMode.eco), closeTo(rep.n, 1e-9));
      expect(rep.n, greaterThan(1));
      expect(rep.n, lessThan(70)); // γ cap 1/(1-γ) ≈ 66.7
    });

    test('forgetting keeps n finite and all outputs bounded', () {
      final ml = RangeMl(estimator: _est());
      _applyUpdates(ml, 300);
      final n = ml.rideCount(RideMode.eco);
      expect(n.isFinite, isTrue);
      expect(n, greaterThan(0));
      expect(n, lessThan(70));
      expect(ml.emaMaeFor(RideMode.eco).isFinite, isTrue);
      for (final m in RideMode.values) {
        // Predictions must stay finite (no NaN/inf) and bounded regardless of
        // extrapolation; exact value may be anything (sparse 3-point training
        // set can overfit with large-but-finite coefficients).
        final v = ml.predict(
          m,
          speedKmh: 25,
          stopsPerKm: 1.0,
          massKg: 100,
          tirePsi: 32,
          tempC: 20,
          headwindKmh: 5,
        );
        expect(v.isFinite, isTrue);
        expect(v.abs(), lessThan(1e6));
        final p = _patterns[0];
        final inSample = ml.predict(
          m,
          speedKmh: p.$1,
          stopsPerKm: p.$2,
          massKg: 100,
          tirePsi: p.$3,
          tempC: p.$4,
          headwindKmh: p.$5,
        );
        expect(inSample.isFinite, isTrue);
        expect(inSample.abs(), lessThan(1e6));
      }
      _expectFiniteJson(ml.toJson());
    });

    test('blend: n=0 is pure physics; β=n/(n+5) tilts toward ML', () {
      final est = _est();
      final ml = RangeMl(estimator: est);
      const speed = 26.0;
      const psi = 32.0;
      const wind = 0.0;
      final physics = est.whPerKmAt(
        speed,
        RideMode.eco,
        tirePsi: psi,
        headwindKmh: wind,
      );
      expect(ml.rideCount(RideMode.eco), 0);
      expect(
        ml.predict(
          RideMode.eco,
          speedKmh: speed,
          stopsPerKm: 1.0,
          massKg: 100,
          tirePsi: psi,
          tempC: 20,
          headwindKmh: wind,
        ),
        closeTo(physics, 1e-12),
      );

      // Exact n = 10 via restored state (JSON roundtrip semantics).
      final seeded = RangeMl(estimator: est, state: _stateWithN(ml, 10));
      expect(seeded.rideCount(RideMode.eco), 10);
      final beta =
          seeded.rideCount(RideMode.eco) / (seeded.rideCount(RideMode.eco) + 5);
      expect(beta, closeTo(10 / 15, 1e-12));

      final rep = _RidgeReplica(RideMode.eco, est); // untouched → seed μ₀
      final x0 = (speed - (RangeEstimator.refSpeed(RideMode.eco) - 5)) / 10.0;
      final yHat = rep.mu[0] * x0; // all other coefficients are 0
      final expected = (1 - beta) * physics + beta * yHat;
      final actual = seeded.predict(
        RideMode.eco,
        speedKmh: speed,
        stopsPerKm: 1.0,
        massKg: 100,
        tirePsi: psi,
        tempC: 20,
        headwindKmh: wind,
      );
      expect(actual, closeTo(expected, 1e-9));
      // The blend moved away from physics toward the ML term.
      expect((actual - physics).abs(), greaterThan(0));
      expect((actual - physics).abs(), lessThan((yHat - physics).abs()));
    });

    test('gating: ML only used at n ≥ 5; below falls back to physics×factor',
        () {
      final est = _est();
      final ml = RangeMl(estimator: est);
      const MlInput input = (
        speedKmh: 26.0,
        stopsPerKm: 1.0,
        massKg: 100,
        tirePsi: 32,
        tempC: 20,
        headwindKmh: 5,
      );
      expect(ml.rideCount(RideMode.eco), 0);
      expect(ml.predictIfEnough(RideMode.eco, input), isNull);

      final below = RangeMl(estimator: est, state: _stateWithN(ml, 4.99));
      expect(below.predictIfEnough(RideMode.eco, input), isNull);

      final atGate = RangeMl(estimator: est, state: _stateWithN(ml, 5));
      expect(atGate.rideCount(RideMode.eco), 5);
      final v = atGate.predictIfEnough(RideMode.eco, input);
      expect(v, isNotNull);
      expect(v!.isFinite, isTrue);

      // RangeEngine path: null mlPredict → identical to physics×factor result.
      final engineNoMl = RangeEngine(
          estimator: est, factors: const RiderFactors(), usableWh: 800);
      final engineWithMl = RangeEngine(
          estimator: est, factors: const RiderFactors(), usableWh: 800);
      final t = Telemetry(
        voltageV: 60,
        currentA: 10,
        socPercent: 80,
        residualAh: 10,
        nominalAh: 20,
        cycleCount: 50,
        cellVolts: const [3.5, 3.5, 3.5, 3.5],
        tempsC: const [],
        charging: false,
        discharging: true,
        protocol: 'test',
        ts: DateTime.now(),
      );
      final a = engineNoMl.report(t, 30, 1.5, tirePsi: 32, weather: null);
      final b = engineWithMl.report(
        t,
        30,
        1.5,
        tirePsi: 32,
        weather: null,
        mlPredict: (m, i) => ml.predictIfEnough(m, i),
      );
      expect(b.ecoKm, a.ecoKm);
      expect(b.sportsKm, a.sportsKm);
      expect(b.hyperKm, a.hyperKm);
      expect(b.liveKm, a.liveKm);
    });

    test('JSON roundtrip preserves mu/L/n/emaMae/featMean/featStd', () {
      final est = _est();
      final ml = RangeMl(estimator: est);
      _applyUpdates(ml, 40);
      final j1 = ml.toJson();
      final restored = RangeMl(estimator: est, state: j1);
      _expectDeepEqual(j1, restored.toJson());
      expect(restored.rideCount(RideMode.eco),
          closeTo(ml.rideCount(RideMode.eco), 1e-9));
      expect(
        restored.emaMaeFor(RideMode.eco),
        closeTo(ml.emaMaeFor(RideMode.eco), 1e-9),
      );
      for (final m in RideMode.values) {
        final p = _patterns[0];
        expect(
          restored.predict(
            m,
            speedKmh: p.$1,
            stopsPerKm: p.$2,
            massKg: 100,
            tirePsi: p.$3,
            tempC: p.$4,
            headwindKmh: p.$5,
          ),
          closeTo(
            ml.predict(
              m,
              speedKmh: p.$1,
              stopsPerKm: p.$2,
              massKg: 100,
              tirePsi: p.$3,
              tempC: p.$4,
              headwindKmh: p.$5,
            ),
            1e-9,
          ),
        );
      }
    });

    test('missing weather (null temp/headwind) is stable and non-throwing', () {
      final ml = RangeMl(estimator: _est());
      final v0 = ml.predict(
        RideMode.eco,
        speedKmh: 22,
        stopsPerKm: 1.0,
        massKg: 100,
        tirePsi: 32,
        tempC: null,
        headwindKmh: null,
      );
      expect(v0.isFinite, isTrue);
      expect(v0, greaterThan(0));
      // Deterministic: identical input → identical result.
      final v0b = ml.predict(
        RideMode.eco,
        speedKmh: 22,
        stopsPerKm: 1.0,
        massKg: 100,
        tirePsi: 32,
        tempC: null,
        headwindKmh: null,
      );
      expect(v0b, v0);

      _applyUpdates(ml, 30, temp: null, wind: null);
      for (final m in RideMode.values) {
        final v = ml.predict(
          m,
          speedKmh: 24,
          stopsPerKm: 0.8,
          massKg: 100,
          tirePsi: 31,
          tempC: null,
          headwindKmh: null,
        );
        expect(v.isFinite, isTrue);
        expect(v, greaterThan(0));
        expect(v, lessThan(200));
      }
      _expectFiniteJson(ml.toJson());
    });
  });

  group('RangeEngine.diagnoseTrip', () {
    DiagnosticResult diagnose(
      RangeEngine engine,
      double ratio, {
      double? tirePsi,
    }) {
      final expected = engine.estimator.whPerKmTrip(
        avgSpeedKmh: 20,
        mode: RideMode.eco,
        stopsPerKm: 1.0,
        tirePsi: tirePsi,
      );
      return engine.diagnoseTrip(
        whPerKmMeasured: expected * ratio,
        mode: RideMode.eco,
        stopsPerKm: 1.0,
        avgSpeedKmh: 20,
        tirePsi: tirePsi,
        daysSinceTyreCheck: 1,
      );
    }

    test('ratio > 1.4 sets drivetrainSuspect with dedicated hint', () {
      final engine = RangeEngine(
        estimator: _est(),
        factors: const RiderFactors(),
        usableWh: 800,
      );
      final d = diagnose(engine, 1.45);
      expect(d.lessRange, isTrue);
      expect(d.drivetrainSuspect, isTrue);
      expect(d.title, 'Consumption far above expected');
      expect(d.hints.first, contains('drivetrain resistance'));
      expect(d.hints.last, contains('Battery'));
    });

    test('1.15 < ratio ≤ 1.4 keeps legacy behavior (flag false)', () {
      final engine = RangeEngine(
        estimator: _est(),
        factors: const RiderFactors(),
        usableWh: 800,
      );
      final d = diagnose(engine, 1.25);
      expect(d.lessRange, isTrue);
      expect(d.drivetrainSuspect, isFalse);
      expect(d.title, 'Less range detected');
      expect(d.hints.any((h) => h.contains('drivetrain resistance')), isFalse);
      expect(d.hints.last, contains('Battery'));
    });

    test('ratio ≤ 1.06 reports in-range, flag false', () {
      final engine = RangeEngine(
        estimator: _est(),
        factors: const RiderFactors(),
        usableWh: 800,
      );
      final d = diagnose(engine, 1.03);
      expect(d.lessRange, isFalse);
      expect(d.drivetrainSuspect, isFalse);
      expect(d.title, 'Efficiency in expected range');
    });
  });
}
