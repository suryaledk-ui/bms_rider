import 'package:bms_rider/src/gps_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  group('buildRideLocationSettings', () {
    test('returns AndroidSettings locked to geolocator 14 API shape', () {
      final s = buildRideLocationSettings();

      // The stream call must be `locationSettings: <AndroidSettings>`; an
      // AndroidSettings instance is what the Android plugin reads via
      // toJson() (there is no nested `androidSettings` key / `accuracyPriority`).
      expect(s, isA<AndroidSettings>());
      expect(s.accuracy, LocationAccuracy.high);
      expect(s.distanceFilter, 2);
      expect(s.timeLimit, isNull);
      expect(s.intervalDuration, const Duration(milliseconds: 500));
      expect(s.forceLocationManager, isFalse);
    });

    test(
        'serializes to the keys the native LocationOptions.parseArguments reads',
        () {
      final json = buildRideLocationSettings().toJson();
      expect(json['accuracy'], LocationAccuracy.high.index);
      expect(json['distanceFilter'], 2);
      expect(json['timeInterval'], 500);
      expect(json['forceLocationManager'], isFalse);
    });
  });
}
