import 'dart:math' as math;

import 'range.dart';

/// Number of features and feature order for the ML range model:
/// [avgSpeedKmh, stopsPerKm, massKg, tirePressurePsi, tempC, headwindKmh].
const int _kFeatures = 6;

/// Online Bayesian ridge regression (with forgetting) predicting Wh/km per
/// ride mode, using the physics estimator as the prior mean.
///
/// Per mode the posterior is kept in precision form:
///   Λ ← γ·Λ + x·xᵀ/σ²,  b ← γ·b + x·y/σ²,  μ = Λ⁻¹b,  n ← γ·n + 1
/// with prior Λ₀ = κI and μ₀ seeded so the model starts at the physics
/// estimate for the mode's reference speed. μ is solved via Gaussian
/// elimination (d=6, no dependencies). Features are normalized online with
/// Welford running mean/std; missing features substitute the stored mean
/// (normalized 0 → no influence).
class RangeMl {
  static const double _kappa = 2.0; // prior precision scalar
  static const double _sigma2 = 9.0; // measurement noise (Wh/km)²
  static const double _gamma = 0.985; // forgetting factor
  static const double _betaDenom = 5.0; // β = n/(n+5)
  static const double _emaAlpha = 0.15; // MAE EMA smoothing

  RangeEstimator estimator;

  final Map<RideMode, _ModeState> _states = {};

  RangeMl({required this.estimator, Map<String, dynamic>? state}) {
    for (final m in RideMode.values) {
      _states[m] = _ModeState.seed(m, estimator);
    }
    if (state != null) {
      for (final m in RideMode.values) {
        final s = state[modeName(m)];
        if (s is Map<String, dynamic>) {
          final restored = _ModeState.fromJson(s);
          if (restored != null) _states[m] = restored;
        }
      }
    }
  }

  /// Swap the physics estimator (after a profile change) keeping ML state.
  void attachEstimator(RangeEstimator e) => estimator = e;

  double rideCount(RideMode mode) => _states[mode]!.n;
  double emaMaeFor(RideMode mode) => _states[mode]!.emaMae;

  /// Blended Wh/km (physics + ML), regardless of the n≥5 gate.
  double predict(
    RideMode mode, {
    required double speedKmh,
    required double stopsPerKm,
    required double massKg,
    required double tirePsi,
    double? tempC,
    double? headwindKmh,
  }) {
    final s = _states[mode]!;
    final x = _features(
      s,
      speedKmh,
      stopsPerKm,
      massKg,
      tirePsi,
      tempC,
      headwindKmh,
    );
    final yHat = _dot(s.mu, x);
    final physics = estimator.whPerKmAt(
      speedKmh,
      mode,
      tirePsi: tirePsi,
      headwindKmh: headwindKmh ?? 0,
    );
    final beta = s.n / (s.n + _betaDenom);
    return (1 - beta) * physics + beta * yHat;
  }

  /// Like [predict] but returns null until the mode has ≥5 completed rides.
  double? predictIfEnough(RideMode mode, MlInput input) {
    if (_states[mode]!.n < 5) return null;
    return predict(
      mode,
      speedKmh: input.speedKmh,
      stopsPerKm: input.stopsPerKm,
      massKg: input.massKg,
      tirePsi: input.tirePsi,
      tempC: input.tempC,
      headwindKmh: input.headwindKmh,
    );
  }

  /// Online update after a completed ride (measured [whPerKm]).
  void update(
    RideMode mode, {
    required double speedKmh,
    required double stopsPerKm,
    required double massKg,
    required double tirePsi,
    double? tempC,
    double? headwindKmh,
    required double whPerKm,
  }) {
    final s = _states[mode]!;
    final x = _featuresAndLearn(
      s,
      speedKmh,
      stopsPerKm,
      massKg,
      tirePsi,
      tempC,
      headwindKmh,
    );

    // Forget older information (γ < 1).
    if (s.n > 0) {
      for (var i = 0; i < _kFeatures; i++) {
        s.b[i] *= _gamma;
        for (var j = 0; j < _kFeatures; j++) {
          s.L[i][j] *= _gamma;
        }
      }
      s.n *= _gamma;
    }

    // Rank-1 observation update: Λ += x·xᵀ/σ², b += x·y/σ².
    final invSigma2 = 1 / _sigma2;
    for (var i = 0; i < _kFeatures; i++) {
      s.b[i] += x[i] * whPerKm * invSigma2;
      for (var j = 0; j < _kFeatures; j++) {
        s.L[i][j] += x[i] * x[j] * invSigma2;
      }
    }
    s.n += 1;

    // Posterior mean μ = Λ⁻¹b.
    s.mu = _solve(s.L, s.b);

    // Track exponentially-weighted MAE of the blended prediction.
    final physics = estimator.whPerKmAt(
      speedKmh,
      mode,
      tirePsi: tirePsi,
      headwindKmh: headwindKmh ?? 0,
    );
    final beta = s.n / (s.n + _betaDenom);
    final blended = (1 - beta) * physics + beta * _dot(s.mu, x);
    s.emaMae = (1 - _emaAlpha) * s.emaMae + _emaAlpha * (blended - whPerKm).abs();
  }

  /// Serialize per-mode model state (small JSON for SharedPreferences).
  Map<String, dynamic> toJson() => {
        for (final m in RideMode.values) modeName(m): _states[m]!.toJson(),
      };

  // ---------------------------------------------------------------------
  // Feature normalization (Welford online mean/std).
  // ---------------------------------------------------------------------

  static List<double> _rawValues(
    double speedKmh,
    double stopsPerKm,
    double massKg,
    double tirePsi,
    double? tempC,
    double? headwindKmh,
  ) =>
      <double>[speedKmh, stopsPerKm, massKg, tirePsi, tempC ?? 0, headwindKmh ?? 0];

  /// Normalize using current stats (prediction path; no Welford update).
  List<double> _features(
    _ModeState s,
    double speedKmh,
    double stopsPerKm,
    double massKg,
    double tirePsi,
    double? tempC,
    double? headwindKmh,
  ) {
    final values = _rawValues(speedKmh, stopsPerKm, massKg, tirePsi, tempC, headwindKmh);
    final x = List<double>.filled(_kFeatures, 0);
    for (var i = 0; i < _kFeatures; i++) {
      final v = values[i];
      // Missing features arrive as 0 placeholder; leave normalized to 0
      // (stored mean) instead of degrading the vector.
      x[i] = (v - s.featMean[i]) / s.stdOf(i);
    }
    return x;
  }

  /// Update Welford stats, then normalize (training path).
  List<double> _featuresAndLearn(
    _ModeState s,
    double speedKmh,
    double stopsPerKm,
    double massKg,
    double tirePsi,
    double? tempC,
    double? headwindKmh,
  ) {
    final values = _rawValues(speedKmh, stopsPerKm, massKg, tirePsi, tempC, headwindKmh);
    final x = List<double>.filled(_kFeatures, 0);
    for (var i = 0; i < _kFeatures; i++) {
      final v = values[i];
      s.updateWelford(i, v);
      x[i] = (v - s.featMean[i]) / s.stdOf(i);
    }
    return x;
  }

  // ---------------------------------------------------------------------
  // Small linear algebra (no dependencies).
  // ---------------------------------------------------------------------

  static double _dot(List<double> a, List<double> b) {
    var acc = 0.0;
    for (var i = 0; i < a.length; i++) {
      acc += a[i] * b[i];
    }
    return acc;
  }

  /// Solve A·x = b by Gauss–Jordan elimination (A is d×d, d=6).
  static List<double> _solve(List<List<double>> a, List<double> b) {
    final n = a.length;
    final m = <List<double>>[
      for (var i = 0; i < n; i++) [...a[i], b[i]],
    ];
    for (var col = 0; col < n; col++) {
      // Partial pivoting.
      var pivot = col;
      for (var r = col + 1; r < n; r++) {
        if (m[r][col].abs() > m[pivot][col].abs()) pivot = r;
      }
      if (m[pivot][col].abs() < 1e-12) continue; // numerically singular
      if (pivot != col) {
        final tmp = m[col];
        m[col] = m[pivot];
        m[pivot] = tmp;
      }
      final pv = m[col][col];
      for (var c = col; c <= n; c++) {
        m[col][c] /= pv;
      }
      for (var r = 0; r < n; r++) {
        if (r == col) continue;
        final f = m[r][col];
        if (f == 0) continue;
        for (var c = col; c <= n; c++) {
          m[r][c] -= f * m[col][c];
        }
      }
    }
    return [for (var i = 0; i < n; i++) m[i][n]];
  }
}

/// Per-mode posterior + feature normalization state.
class _ModeState {
  List<double> mu = List.filled(_kFeatures, 0);
  List<List<double>> L = List.generate(_kFeatures, (_) => List.filled(_kFeatures, 0));
  List<double> b = List.filled(_kFeatures, 0);
  double n = 0;
  double emaMae = 0;

  // Welford per-feature statistics.
  List<double> featMean = List.filled(_kFeatures, 0);
  List<double> featM2 = List.filled(_kFeatures, 0);
  List<double> featCount = List.filled(_kFeatures, 10);

  /// Empty state (used when restoring from JSON).
  _ModeState();

  /// Fresh model: prior Λ₀ = κI, μ₀ = physics seed, Welford pseudo-counts.
  _ModeState.seed(RideMode mode, RangeEstimator estimator) {
    for (var i = 0; i < _kFeatures; i++) {
      L[i][i] = RangeMl._kappa;
    }
    // Physics prior: anchor the speed coefficient so that at the mode's
    // reference speed the prediction equals the physics estimate. Initial
    // normalization stats are chosen deterministically: speed mean =
    // refSpeed − 5 with std 10 → normalized ref speed = 0.5, so
    // μ₀[speed] = physics / 0.5. Other coefficients stay ≈ 0.
    final refSpeed = RangeEstimator.refSpeed(mode);
    final physics = estimator.whPerKmAt(refSpeed, mode, tirePsi: 32, headwindKmh: 0);
    mu[0] = physics / 0.5;
    b = [for (var i = 0; i < _kFeatures; i++) RangeMl._kappa * mu[i]];

    // Welford seeds: pseudo-count 10 with typical values so normalization is
    // stable from the first ride (and missing-weather features stay sane).
    const means = [0.0, 1.0, 140.0, 32.0, 22.0, 5.0];
    const stds = [10.0, 1.0, 25.0, 6.0, 10.0, 8.0];
    for (var i = 0; i < _kFeatures; i++) {
      featMean[i] = means[i];
      featM2[i] = 10.0 * stds[i] * stds[i];
      featCount[i] = 10.0;
    }
    // Speed seed uses the mode reference (overrides means[0]).
    featMean[0] = refSpeed - 5;
  }

  void updateWelford(int i, double v) {
    final k = featCount[i] + 1;
    final delta = v - featMean[i];
    featMean[i] += delta / k;
    featM2[i] += delta * (v - featMean[i]);
    featCount[i] = k;
  }

  double stdOf(int i) {
    final k = featCount[i];
    if (k < 2) return 1.0;
    final variance = featM2[i] / k;
    return variance < 1e-6 ? 1.0 : math.sqrt(variance);
  }

  Map<String, dynamic> toJson() => {
        'mu': mu,
        'L': L,
        'b': b,
        'n': n,
        'emaMae': emaMae,
        'featMean': featMean,
        'featStd': [for (var i = 0; i < _kFeatures; i++) stdOf(i)],
        'featCount': featCount,
      };

  /// Restore from JSON; returns null (caller keeps seed) on malformed data.
  static _ModeState? fromJson(Map<String, dynamic> json) {
    try {
      final s = _ModeState();
      s.mu = _numList(json['mu']);
      s.b = _numList(json['b']);
      final L = json['L'];
      if (L is List && L.length == _kFeatures) {
        for (var i = 0; i < _kFeatures; i++) {
          final row = L[i];
          if (row is List && row.length == _kFeatures) {
            for (var j = 0; j < _kFeatures; j++) {
              s.L[i][j] = (row[j] as num).toDouble();
            }
          }
        }
      }
      s.n = (json['n'] as num).toDouble();
      s.emaMae = (json['emaMae'] as num?)?.toDouble() ?? 0;
      s.featMean = _numList(json['featMean']);
      final stds = _numList(json['featStd']);
      final counts = _numList(json['featCount']);
      for (var i = 0; i < _kFeatures; i++) {
        s.featCount[i] = math.max(counts[i], 0.0).toDouble();
        s.featM2[i] = stds[i] * stds[i] * s.featCount[i];
      }
      s.mu = RangeMl._solve(s.L, s.b); // recompute for consistency
      return s;
    } catch (_) {
      return null;
    }
  }

  static List<double> _numList(Object? v) {
    if (v is List && v.length == _kFeatures) {
      return [for (final e in v) (e as num).toDouble()];
    }
    return List.filled(_kFeatures, 0);
  }
}
