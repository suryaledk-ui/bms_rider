import 'dart:math' as math;

import 'models.dart';
import 'weather.dart';

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

/// Predefined vehicle profiles for the app's target segment (generic Chinese
/// packs + Komaki class). Selecting one seeds the physics priors (mass,
/// usable Wh, drag) so estimates are accurate from the first ride.
class VehiclePreset {
  final String id;
  final String name;
  final String subtitle;
  final double scooterKg;
  final double usableWh;
  final double cdA;
  final double crr;
  final double ratedPhi;
  final double topSpeedKmh;
  final String packLabel;

  const VehiclePreset({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.scooterKg,
    required this.usableWh,
    required this.cdA,
    required this.crr,
    required this.ratedPhi,
    required this.topSpeedKmh,
    required this.packLabel,
  });
}

const List<VehiclePreset> vehiclePresets = [
  VehiclePreset(
    id: 'generic_48v20ah',
    name: 'Generic 48V 20Ah',
    subtitle: '800W hub · ~0.96 kWh · ≤35 km/h',
    scooterKg: 80,
    usableWh: 880,
    cdA: 0.58,
    crr: 0.018,
    ratedPhi: 32,
    topSpeedKmh: 35,
    packLabel: '48V 20Ah',
  ),
  VehiclePreset(
    id: 'generic_60v20ah',
    name: 'Generic 60V 20Ah',
    subtitle: '800–1000W hub · ~1.20 kWh · ≤45 km/h',
    scooterKg: 85,
    usableWh: 1100,
    cdA: 0.58,
    crr: 0.018,
    ratedPhi: 32,
    topSpeedKmh: 45,
    packLabel: '60V 20Ah',
  ),
  VehiclePreset(
    id: 'generic_60v30ah',
    name: 'Generic 60V 30Ah',
    subtitle: '1000–1200W hub · ~1.80 kWh · ≤50 km/h',
    scooterKg: 95,
    usableWh: 1660,
    cdA: 0.60,
    crr: 0.018,
    ratedPhi: 32,
    topSpeedKmh: 50,
    packLabel: '60V 30Ah',
  ),
  VehiclePreset(
    id: 'generic_72v30ah',
    name: 'Generic 72V 30Ah',
    subtitle: '1200–1500W hub · ~2.16 kWh · ≤55 km/h',
    scooterKg: 100,
    usableWh: 1990,
    cdA: 0.60,
    crr: 0.018,
    ratedPhi: 32,
    topSpeedKmh: 55,
    packLabel: '72V 30Ah',
  ),
  VehiclePreset(
    id: 'komaki_se_eco',
    name: 'Komaki SE (Eco)',
    subtitle: '62V 35Ah · ~2.17 kWh · 3kW hub · ≤60 km/h',
    scooterKg: 100,
    usableWh: 2000,
    cdA: 0.65,
    crr: 0.016,
    ratedPhi: 32,
    topSpeedKmh: 60,
    packLabel: '62V 35Ah',
  ),
  VehiclePreset(
    id: 'komaki_se_sport',
    name: 'Komaki SE (Sport)',
    subtitle: '74V 44Ah · ~3.26 kWh · 3kW/5.2kW · ≤80 km/h',
    scooterKg: 100,
    usableWh: 3000,
    cdA: 0.65,
    crr: 0.016,
    ratedPhi: 32,
    topSpeedKmh: 80,
    packLabel: '74V 44Ah',
  ),
  VehiclePreset(
    id: 'komaki_xgt_km',
    name: 'Komaki XGT KM',
    subtitle: '60V 34Ah · ~2.04 kWh · licence-free ≤25 km/h',
    scooterKg: 90,
    usableWh: 1880,
    cdA: 0.60,
    crr: 0.018,
    ratedPhi: 32,
    topSpeedKmh: 25,
    packLabel: '60V 34Ah',
  ),
  VehiclePreset(
    id: 'komaki_xone',
    name: 'Komaki X-One (1.75–2.2 kWh)',
    subtitle: 'LiFePO4 · 2kW hub · ≤50–60 km/h',
    scooterKg: 85,
    usableWh: 1840,
    cdA: 0.60,
    crr: 0.017,
    ratedPhi: 32,
    topSpeedKmh: 55,
    packLabel: 'LiFePO4 1.75–2.2 kWh',
  ),
];

/// Coulomb/physics consumption model for the Chinese scooter class.
///
/// EC_battery [Wh/km] = (0.5·ρ·CdA·v² + Crr·m·g + m·g·sinθ + m·a) / (3.6·η)
///                    + P_aux / v   (v in m/s inside the bracket; km/h outside)
class RangeEstimator {
  static const double kRho = 1.225; // kg/m3
  static const double kG = 9.81;
  static const double kPaux = 3.0; // W

  final double cdA;
  final double crrBase;
  final double massKg; // total scooter + rider

  RangeEstimator({
    required this.massKg,
    this.cdA = 0.48,
    this.crrBase = 0.018,
  });

  double _eta(RideMode m) => switch (m) {
        RideMode.eco => 0.74,
        RideMode.sports => 0.78,
        RideMode.hyper => 0.80,
      };

  /// Reference speeds used for per-mode range cards.
  static double refSpeed(RideMode m) => switch (m) {
        RideMode.eco => 20,
        RideMode.sports => 36,
        RideMode.hyper => 47,
      };

  /// Rolling resistance correction from tyre pressure (psi).
  /// Research: ~3% range lost per 1 psi below spec; Crr ∝ P^-0.5.
  double crrAtPressure(double psi, {double ratedPsi = 32}) {
    if (psi <= 0) return crrBase;
    final ratio = psi / ratedPsi;
    return crrBase * math.pow(ratio, -0.5).toDouble();
  }

  /// Predicted battery consumption (Wh/km) at steady speed.
  double whPerKmAt(
    double kmh,
    RideMode mode, {
    double? tirePsi,
    double? headwindKmh,
  }) {
    final v = kmh / 3.6; // m/s
    final crr = crrAtPressure(tirePsi ?? 32);
    final fRoll = crr * massKg * kG;
    final vEff = v + (headwindKmh ?? 0) / 3.6;
    final fAero = 0.5 * kRho * cdA * vEff * vEff;
    final fTotal = fRoll + fAero;
    final ec = fTotal / (3.6 * _eta(mode));
    return ec + kPaux / math.max(kmh, 5.0);
  }

  double whPerKmForMode(RideMode mode,
      {WeatherInfo? weather, double? tirePsi}) {
    final v = refSpeed(mode);
    final hw = weather?.headwindKmh(90) ?? 0; // course-agnostic default
    return whPerKmAt(v, mode, tirePsi: tirePsi, headwindKmh: hw);
  }

  /// Trip consumption (Wh/km) with stop-go correction from stops/km.
  double whPerKmTrip({
    required double avgSpeedKmh,
    required RideMode mode,
    required double stopsPerKm,
    double? tirePsi,
    WeatherInfo? weather,
  }) {
    final base = whPerKmAt(avgSpeedKmh, mode, tirePsi: tirePsi);
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

  RiderFactors updated(RideMode m, double measuredVsPredicted,
      {double alpha = 0.12}) {
    final k = modeName(m);
    final cur = factorFor(m);
    final next = cur + alpha * (measuredVsPredicted - cur);
    return RiderFactors({...factors, k: next.clamp(0.7, 1.4)});
  }
}

/// Feature inputs for the ML range model (see ml_range.dart).
typedef MlInput = ({
  double speedKmh,
  double stopsPerKm,
  double massKg,
  double tirePsi,
  double? tempC,
  double? headwindKmh,
});

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

  /// True when measured consumption is >1.4× the physics expectation, which
  /// strongly points at drivetrain resistance (brakes/bearings/wheels).
  final bool drivetrainSuspect;

  const DiagnosticResult({
    required this.lessRange,
    required this.title,
    required this.hints,
    this.drivetrainSuspect = false,
  });
}

class RangeEngine {
  final RangeEstimator estimator;
  RiderFactors factors;

  double usableWh; // measured/estimated usable pack energy

  RangeEngine(
      {required this.estimator, required this.factors, required this.usableWh});

  RangeReport report(
    Telemetry t,
    double currentSpeedKmh,
    double stopsPerKm, {
    WeatherInfo? weather,
    double? tirePsi,
    int cutoffSocPercent = 0,
    double? Function(RideMode mode, MlInput input)? mlPredict,
  }) {
    // A scooter controller often cuts off before the BMS reports 0%
    // (e.g. stops at 52–54 V while BMS still shows 15–25%). Treat that
    // dead band as unusable: only the SOC range above the cutoff counts.
    final cutoff = cutoffSocPercent.clamp(0, 90).toDouble();
    final span = 100.0 - cutoff;
    final frac =
        span <= 0 ? 1.0 : ((t.socPercent - cutoff) / span).clamp(0.0, 1.0);
    final energyNow = usableWh * frac;

    double kmFor(RideMode m) {
      // ML (when warm: n ≥ 5) replaces physics×factor for the stable mode
      // rows; otherwise keep the existing learned-factor path.
      final ml = mlPredict?.call(
        m,
        (
          speedKmh: RangeEstimator.refSpeed(m),
          stopsPerKm: stopsPerKm,
          massKg: estimator.massKg,
          tirePsi: tirePsi ?? 32,
          tempC: weather?.tempC,
          headwindKmh: weather?.headwindKmh(90),
        ),
      );
      final ec = ml ??
          (estimator.whPerKmForMode(m, weather: weather, tirePsi: tirePsi) *
              factors.factorFor(m));
      return energyNow / ec;
    }

    final liveMode = modeForSpeed(currentSpeedKmh);
    final liveEc =
        estimator.whPerKmAt(currentSpeedKmh, liveMode, tirePsi: tirePsi) *
            factors.factorFor(liveMode);
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
    // Research-based capacity fade: consumer NMC ~80% at 900–1400 cycles.
    var soh = 100.0 - cycles * 0.018;
    if (calibratedSoH != null) soh = calibratedSoH;
    soh -= t.cellSpreadMv * 0.05;
    soh = soh.clamp(20.0, 100.0);

    // Voltage sag proxy (only when discharging under load).
    var sag = 0.0;
    if (t.currentA > 5 && t.voltageV > 0) {
      final estOver =
          t.nominalAh > 0 ? t.currentA / t.nominalAh : 0.0; // C-rate
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
    WeatherInfo? weather,
    double? tirePsi,
    int daysSinceTyreCheck = 999,
  }) {
    final expected = estimator.whPerKmTrip(
          avgSpeedKmh: avgSpeedKmh,
          mode: mode,
          stopsPerKm: stopsPerKm,
          tirePsi: tirePsi,
          weather: weather,
        ) *
        factors.factorFor(mode);
    final ratio = whPerKmMeasured / expected;

    if (ratio < 1.06) {
      return const DiagnosticResult(
        lessRange: false,
        title: 'Efficiency in expected range',
        hints: [],
      );
    }

    final over = ((ratio - 1.0) * 100).round();
    final hints = <String>[
      'Consumption is $over% above expected for ${modeName(mode)} mode.',
      if (weather != null && weather.windSpeedKmh > 8)
        '1 · Weather/wind: ${weather.windSpeedKmh.toStringAsFixed(0)} km/h wind '
            '(${weather.tempC.toStringAsFixed(0)}°C) strongly affects consumption.',
      if (weather != null && weather.tempC < 10)
        '2 · Cold battery: ~${((10 - weather.tempC) * 1.5).round()}% capacity loss at '
            '${weather.tempC.toStringAsFixed(0)}°C — expected in winter.',
      '2 · Tyre pressure: check and inflate (low pressure raises rolling loss).',
      '3 · Drivetrain drag: check brake drag, bearings, wheel alignment.',
      '4 · Riding style: hard acceleration and stop-go raises consumption.',
      if (stopsPerKm > 2.0)
        '5 · Many stops (${stopsPerKm.toStringAsFixed(1)}/km) — expected for city riding.',
      if (daysSinceTyreCheck > 30)
        '6 · Tyre not checked in 30+ days — do it now.',
      'Battery itself is NOT the primary suspect — SOH is shown separately.',
    ];

    if (ratio > 1.4) {
      hints.insert(
        0,
        'Check brakes, bearings, wheel alignment and tires — consumption is '
        '>1.4× above expected (>1.4× = likely drivetrain resistance).',
      );
      return DiagnosticResult(
        lessRange: true,
        title: 'Consumption far above expected',
        hints: hints,
        drivetrainSuspect: true,
      );
    }

    return DiagnosticResult(
      lessRange: true,
      title: 'Less range detected',
      hints: hints,
    );
  }
}
