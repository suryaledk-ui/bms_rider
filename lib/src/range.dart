import 'dart:math' as math;

import 'models.dart';

enum RideMode { eco, sports, hyper }

String modeName(RideMode m) => switch (m) {
      RideMode.eco => 'Eco',
      RideMode.sports => 'Sports',
      RideMode.hyper => 'Hyper',
    };

/// [RideMode] for a given instantaneous speed.
RideMode modeForSpeed(double kmh) {
  if (kmh <= 30) return RideMode.eco;
  if (kmh <= 42) return RideMode.sports;
  return RideMode.hyper;
}

/// Coulomb/physics consumption model for the Chinese scooter class.
///
/// EC_battery [Wh/km] = (0.5·ρ·CdA·v² + Crr·m·g + m·g·sinθ + m·a) / (3.6·η)
///                    + P_aux / v   (v in m/s inside the bracket; km/h outside)
class RangeEstimator {
  static const double kRho = 1.225; // kg/m3
  static const double kCdA = 0.48; // m2
  static const double kCrr = 0.018;
  static const double kG = 9.81;
  static const double kPaux = 3.0; // W
  static const double kEtaEco = 0.74;
  static const double kEtaSports = 0.78;
  static const double kEtaHyper = 0.80;

  double massKg; // total scooter + rider

  RangeEstimator({required this.massKg});

  double _eta(RideMode m) => switch (m) {
        RideMode.eco => kEtaEco,
        RideMode.sports => kEtaSports,
        RideMode.hyper => kEtaHyper,
      };

  /// Reference speeds used for per-mode range cards.
  static double refSpeed(RideMode m) => switch (m) {
        RideMode.eco => 20,
        RideMode.sports => 36,
        RideMode.hyper => 47,
      };

  /// Predicted battery consumption (Wh/km) at steady speed.
  double whPerKmAt(double kmh, RideMode mode) {
    final v = kmh / 3.6; // m/s
    final fRoll = kCrr * massKg * kG;
    final fAero = 0.5 * kRho * kCdA * v * v;
    final fTotal = fRoll + fAero;
    final ec = fTotal / (3.6 * _eta(mode));
    return ec + kPaux / math.max(kmh, 5.0);
  }

  double whPerKmForMode(RideMode mode) => whPerKmAt(refSpeed(mode), mode);

  /// Trip consumption (Wh/km) with stop-go correction from stops/km.
  double whPerKmTrip({
    required double avgSpeedKmh,
    required RideMode mode,
    required double stopsPerKm,
  }) {
    final base = whPerKmAt(avgSpeedKmh, mode);
    final kStopGo = 1.0 + math.min(stopsPerKm * 0.06, 0.4);
    return base * kStopGo;
  }
}

/// Learned per-rider correction factors (stored in prefs as [mode -> factor]).
class RiderFactors {
  final Map<String, double> factors;
  const RiderFactors([this.factors = const {}]);

  double factorFor(RideMode m) {
    final k = modeName(m);
    return factors[k] ?? 1.0;
  }

  RiderFactors updated(RideMode m, double measuredVsPredicted, {double alpha = 0.12}) {
    final k = modeName(m);
    final cur = factorFor(m);
    final next = cur + alpha * (measuredVsPredicted - cur);
    return RiderFactors({...factors, k: next.clamp(0.7, 1.4)});
  }
}

class RangeReport {
  final double ecoKm;
  final double sportsKm;
  final double hyperKm;
  final double liveKm; // at current speed
  final RideMode liveMode;
  const RangeReport({
    required this.ecoKm,
    required this.sportsKm,
    required this.hyperKm,
    required this.liveKm,
    required this.liveMode,
  });
}

class BatteryHealth {
  final double sohPercent;
  final int cycles;
  final double cellSpreadMv;
  final double sagDropV;
  final String note;
  const BatteryHealth({
    required this.sohPercent,
    required this.cycles,
    required this.cellSpreadMv,
    required this.sagDropV,
    required this.note,
  });
}

class DiagnosticResult {
  final bool lessRange;
  final String title;
  final List<String> hints;
  const DiagnosticResult({required this.lessRange, required this.title, required this.hints});
}

class RangeEngine {
  final RangeEstimator estimator;
  RiderFactors factors;

  double usableWh; // measured/estimated usable pack energy

  RangeEngine({required this.estimator, required this.factors, required this.usableWh});

  RangeReport report(Telemetry t, double currentSpeedKmh, double stopsPerKm) {
    final soc = (t.socPercent.clamp(0, 100)) / 100.0;
    final energyNow = usableWh * soc;

    double kmFor(RideMode m) {
      final factor = factors.factorFor(m);
      final ec = estimator.whPerKmForMode(m) * factor;
      return energyNow / ec;
    }

    final liveMode = modeForSpeed(currentSpeedKmh);
    final liveEc = estimator.whPerKmAt(currentSpeedKmh, liveMode) * factors.factorFor(liveMode);
    final liveKm = energyNow / liveEc;

    return RangeReport(
      ecoKm: kmFor(RideMode.eco),
      sportsKm: kmFor(RideMode.sports),
      hyperKm: kmFor(RideMode.hyper),
      liveKm: liveKm,
      liveMode: liveMode,
    );
  }

  BatteryHealth health(Telemetry t, {double? calibratedSoH}) {
    final cycles = t.cycleCount;
    // Degradation model: ~35% fade over 2000 cycles, plus spread penalty.
    var soh = 100.0 - cycles * 0.018;
    if (calibratedSoH != null) soh = calibratedSoH;
    soh -= t.cellSpreadMv * 0.05;
    soh = soh.clamp(20.0, 100.0);

    // Voltage sag proxy (only when discharging under load).
    var sag = 0.0;
    if (t.currentA > 5 && t.voltageV > 0) {
      final estOver = t.nominalAh > 0 ? t.currentA / t.nominalAh : 0.0; // C-rate
      sag = math.min(estOver * 2.5, 6.0);
    }

    String note;
    if (soh >= 90) {
      note = 'Battery healthy';
    } else if (soh >= 75) {
      note = 'Normal aging — monitor cycles';
    } else {
      note = 'Battery aged — consider replacement soon';
    }
    if (t.cellSpreadMv > 150) note += ' · cell imbalance high';

    return BatteryHealth(
      sohPercent: soh,
      cycles: cycles,
      cellSpreadMv: t.cellSpreadMv,
      sagDropV: sag,
      note: note,
    );
  }

  /// Compare measured trip efficiency vs physics expectation (with rider
  /// factor). Returns a diagnostic.
  DiagnosticResult diagnoseTrip({
    required double whPerKmMeasured,
    required RideMode mode,
    required double stopsPerKm,
    required double avgSpeedKmh,
  }) {
    final expected = estimator.whPerKmTrip(
          avgSpeedKmh: avgSpeedKmh,
          mode: mode,
          stopsPerKm: stopsPerKm,
        ) *
        factors.factorFor(mode);
    final ratio = whPerKmMeasured / expected;

    if (ratio < 1.10) {
      return const DiagnosticResult(
        lessRange: false,
        title: 'Efficiency in expected range',
        hints: [],
      );
    }

    final over = ((ratio - 1.0) * 100).round();
    final hints = <String>[
      'Consumption is $over% above expected for ${modeName(mode)} mode.',
      '1 · Weather/wind: headwind strongly increases consumption.',
      '2 · Tyre pressure: check and inflate (low pressure raises rolling loss).',
      '3 · Drivetrain drag: check brake drag, bearings, wheel alignment.',
      '4 · Riding style: hard acceleration and stop-go raises consumption.',
      if (stopsPerKm > 2.0) '5 · Many stops (${stopsPerKm.toStringAsFixed(1)}/km) — expected for city riding.',
      'Battery itself is NOT the primary suspect — SOH is shown separately.',
    ];
    return DiagnosticResult(
      lessRange: true,
      title: 'Less range detected',
      hints: hints,
    );
  }
}
