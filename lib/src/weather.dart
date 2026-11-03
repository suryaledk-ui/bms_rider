import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// Ambient weather at ride time (Open-Meteo free API, no key required).
class WeatherInfo {
  final double tempC;
  final double windSpeedKmh; // 10 m wind speed
  final double windDirectionDeg; // 0 = North, 90 = East
  final DateTime fetchedAt;

  const WeatherInfo({
    required this.tempC,
    required this.windSpeedKmh,
    required this.windDirectionDeg,
    required this.fetchedAt,
  });

  /// Headwind component (km/h) against the rider's course [headingDeg].
  /// streetFactor ≈ 0.7 dampens API wind to street canyon reality.
  double headwindKmh(double headingDeg, {double streetFactor = 0.7}) {
    final rad = (windDirectionDeg - headingDeg) * math.pi / 180.0;
    return windSpeedKmh * math.cos(rad) * streetFactor;
  }
}

/// Fetch current weather for [lat],[lon]. Returns null on any failure
/// (offline, API down) — the app must degrade gracefully.
Future<WeatherInfo?> fetchWeather(double lat, double lon) async {
  final url = Uri.parse(
    'https://api.open-meteo.com/v1/forecast'
    '?latitude=${lat.toStringAsFixed(4)}&longitude=${lon.toStringAsFixed(4)}'
    '&current=temperature_2m,wind_speed_10m,wind_direction_10m'
    '&wind_speed_unit=kmh&timezone=UTC',
  );
  try {
    final res = await http.get(url).timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final cur = data['current'] as Map<String, dynamic>?;
    if (cur == null) return null;
    return WeatherInfo(
      tempC: (cur['temperature_2m'] as num).toDouble(),
      windSpeedKmh: (cur['wind_speed_10m'] as num).toDouble(),
      windDirectionDeg: (cur['wind_direction_10m'] as num).toDouble(),
      fetchedAt: DateTime.now(),
    );
  } catch (_) {
    return null;
  }
}
