import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';
import 'range.dart';

class AppStore {
  Database? _db;
  SharedPreferences? prefs;

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    _db = await openDatabase(
      p.join(await getDatabasesPath(), 'bms_rider.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE rides(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_ms INTEGER NOT NULL,
            end_ms INTEGER NOT NULL,
            distance_m REAL NOT NULL,
            duration_s REAL NOT NULL,
            wh_used REAL NOT NULL,
            wh_regen REAL NOT NULL,
            wh_per_km REAL NOT NULL,
            avg_speed REAL NOT NULL,
            max_speed REAL NOT NULL,
            soc_start INTEGER NOT NULL,
            soc_end INTEGER NOT NULL,
            protocol TEXT NOT NULL,
            stops INTEGER NOT NULL DEFAULT 0,
            mode_seconds TEXT NOT NULL DEFAULT '{}'
          )
        ''');
      },
    );
  }

  // -- prefs --
  String? get savedDeviceId => prefs?.getString('saved_device_id');
  Future<void> setSavedDeviceId(String id) async => prefs?.setString('saved_device_id', id);

  double get riderWeightKg => prefs?.getDouble('rider_weight_kg') ?? 70.0;
  Future<void> setRiderWeightKg(double v) async => prefs?.setDouble('rider_weight_kg', v);

  double get scooterWeightKg => prefs?.getDouble('scooter_weight_kg') ?? 80.0;
  Future<void> setScooterWeightKg(double v) async => prefs?.setDouble('scooter_weight_kg', v);

  double get tirePressurePsi => prefs?.getDouble('tire_pressure_psi') ?? 32.0;
  Future<void> setTirePressurePsi(double v) async => prefs?.setDouble('tire_pressure_psi', v);

  DateTime? get tirePressureCheckedAt {
    final ms = prefs?.getInt('tire_pressure_checked_ms');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setTirePressureCheckedAt(DateTime t) async =>
      prefs?.setInt('tire_pressure_checked_ms', t.millisecondsSinceEpoch);

  double get usableWh => prefs?.getDouble('usable_wh') ?? 960.0; // 48V20Ah default
  Future<void> setUsableWh(double v) async => prefs?.setDouble('usable_wh', v);

  String get vehiclePresetId => prefs?.getString('vehicle_preset_id') ?? 'generic_48v20ah';
  Future<void> setVehiclePresetId(String v) async => prefs?.setString('vehicle_preset_id', v);

  double? get calibratedSoH => prefs?.getDouble('calibrated_soh');

  Future<void> setCalibratedSoH(double v) async => prefs?.setDouble('calibrated_soh', v);

  RiderFactors get factors {
    final raw = prefs?.getString('rider_factors');
    if (raw == null) return const RiderFactors();
    try {
      final map = (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble()));
      return RiderFactors(map);
    } catch (_) {
      return const RiderFactors();
    }
  }

  Future<void> saveFactors(RiderFactors f) async {
    await prefs?.setString('rider_factors', jsonEncode(f.factors));
  }

  // -- rides --
  Future<int> insertTrip(Trip t) async {
    return _db!.insert('rides', {
      'start_ms': t.start.millisecondsSinceEpoch,
      'end_ms': t.end.millisecondsSinceEpoch,
      'distance_m': t.distanceM,
      'duration_s': t.durationS,
      'wh_used': t.whUsed,
      'wh_regen': t.whRegen,
      'wh_per_km': t.whPerKm,
      'avg_speed': t.avgSpeedKmh,
      'max_speed': t.maxSpeedKmh,
      'soc_start': t.socStart,
      'soc_end': t.socEnd,
      'protocol': t.protocol,
      'stops': t.stops,
      'mode_seconds': jsonEncode(t.modeSeconds),
    });
  }

  Future<List<Trip>> rides() async {
    final rows = await _db!.query('rides', orderBy: 'start_ms DESC', limit: 200);
    return rows.map((r) {
      Map<String, dynamic> modes = {};
      try {
        modes = (jsonDecode(r['mode_seconds'] as String) as Map).cast<String, dynamic>();
      } catch (_) {}
      return Trip(
        id: r['id'] as int,
        start: DateTime.fromMillisecondsSinceEpoch(r['start_ms'] as int),
        end: DateTime.fromMillisecondsSinceEpoch(r['end_ms'] as int),
        distanceM: (r['distance_m'] as num).toDouble(),
        durationS: (r['duration_s'] as num).toDouble(),
        whUsed: (r['wh_used'] as num).toDouble(),
        whRegen: (r['wh_regen'] as num).toDouble(),
        whPerKm: (r['wh_per_km'] as num).toDouble(),
        avgSpeedKmh: (r['avg_speed'] as num).toDouble(),
        maxSpeedKmh: (r['max_speed'] as num).toDouble(),
        socStart: r['soc_start'] as int,
        socEnd: r['soc_end'] as int,
        protocol: r['protocol'] as String,
        stops: r['stops'] as int,
        modeSeconds: modes,
      );
    }).toList();
  }
}
