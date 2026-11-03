import 'package:bms_rider/src/controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpeedFilter', () {
    test('dead zone: raw < 2.5 km/h always yields 0', () {
      final f = SpeedFilter();
      for (final raw in [0.0, 0.4, 1.2, 2.49]) {
        expect(f.update(raw), 0);
        expect(f.smoothed, 0);
      }
      // Stays 0 even after motion then stop.
      expect(f.update(30), greaterThan(0));
      expect(f.update(1.0), 0);
      expect(f.update(0.0), 0);
    });

    test('>= 5 km/h applies EMA and marks moving', () {
      final f = SpeedFilter();
      expect(f.update(10), closeTo(2.5, 1e-9)); // 10 * 0.25
      expect(f.wasMoving, isTrue);
      expect(f.update(12), closeTo(2.5 + (12 - 2.5) * 0.25, 1e-9));
    });

    test('ambiguous band from stationary requires 2 consecutive > 3 km/h', () {
      final f = SpeedFilter();
      expect(f.update(4.0), 0); // streak 1 → still 0
      expect(f.update(4.2), greaterThan(0)); // streak 2 → adopt motion
      expect(f.update(3.5), greaterThan(0)); // wasMoving → EMA continues
      expect(f.update(1.0), 0); // back to dead zone
      expect(f.update(4.0), 0); // streak 1 again (wasMoving false)
      expect(f.update(2.9), 0); // below 3 → streak reset
      expect(f.update(4.0), 0); // streak 1
      expect(f.update(4.1), greaterThan(0)); // streak 2 → adopt
    });

    test('jitter spikes never reach streak 2 → stays 0', () {
      final f = SpeedFilter();
      for (final raw in [3.2, 2.8, 3.5, 2.9, 3.1, 2.7, 4.9, 2.9]) {
        expect(f.update(raw), 0);
      }
      expect(f.smoothed, 0);
      expect(f.wasMoving, isFalse);
    });

    test('coast-down through band keeps EMA when recently moving', () {
      final f = SpeedFilter();
      f.update(30);
      final s1 = f.update(15);
      expect(s1, greaterThan(0));
      final s2 = f.update(4.5); // band but wasMoving → EMA
      expect(s2, greaterThan(0));
      expect(s2, lessThan(s1));
      final s3 = f.update(4.0);
      expect(s3, greaterThan(0));
      expect(s3, lessThan(s2));
      expect(f.update(2.0), 0); // dead zone clears wasMoving
      expect(f.wasMoving, isFalse);
    });

    test('reset clears state', () {
      final f = SpeedFilter();
      f.update(30);
      f.reset();
      expect(f.smoothed, 0);
      expect(f.wasMoving, isFalse);
      expect(f.update(4.0), 0); // must re-earn the streak
      expect(f.update(4.1), greaterThan(0));
    });
  });
}
