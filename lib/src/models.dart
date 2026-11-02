// Core data models shared across the app.

class Telemetry {
  final double voltageV;
  final double currentA; // positive = discharging, negative = charging/regen
  final int socPercent;
  final double residualAh;
  final double nominalAh;
  final int cycleCount;
  final List<double> cellVolts; // volts
  final List<double> tempsC;
  final bool charging;
  final bool discharging;
  final String protocol;
  final DateTime ts;

  const Telemetry({
    required this.voltageV,
    required this.currentA,
    required this.socPercent,
    required this.residualAh,
    required this.nominalAh,
    required this.cycleCount,
    required this.cellVolts,
    required this.tempsC,
    required this.charging,
    required this.discharging,
    required this.protocol,
    required this.ts,
  });

  double get powerW => voltageV * currentA; // + = discharge draw

  double get cellMinV => cellVolts.isEmpty ? 0 : cellVolts.reduce((a, b) => a < b ? a : b);
  double get cellMaxV => cellVolts.isEmpty ? 0 : cellVolts.reduce((a, b) => a > b ? a : b);
  double get cellSpreadMv => (cellMaxV - cellMinV) * 1000;

  @override
  String toString() =>
      'Telemetry($protocol ${voltageV.toStringAsFixed(1)}V ${currentA.toStringAsFixed(1)}A '
      '$socPercent% cells=${cellVolts.length})';
}

class Trip {
  final int id; // 0 until saved
  final DateTime start;
  final DateTime end;
  final double distanceM;
  final double durationS;
  final double whUsed;
  final double whRegen;
  final double whPerKm;
  final double avgSpeedKmh;
  final double maxSpeedKmh;
  final int socStart;
  final int socEnd;
  final String protocol;
  final int stops;
  final Map<String, dynamic> modeSeconds; // seconds spent in each mode

  const Trip({
    this.id = 0,
    required this.start,
    required this.end,
    required this.distanceM,
    required this.durationS,
    required this.whUsed,
    required this.whRegen,
    required this.whPerKm,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.socStart,
    required this.socEnd,
    required this.protocol,
    required this.stops,
    required this.modeSeconds,
  });

  double get distanceKm => distanceM / 1000.0;
  String get durationLabel {
    final d = durationS ~/ 60;
    final h = d ~/ 60;
    final m = d % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m ${(durationS % 60).round()}s';
  }
}

class ScanCandidate {
  final String id;
  final String name;
  final String guess; // protocol family guess
  final bool bonded;
  const ScanCandidate({required this.id, required this.name, required this.guess, required this.bonded});
}
