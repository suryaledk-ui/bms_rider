import 'package:geolocator/geolocator.dart';

/// Builds the exact Android LocationSettings used by ride GPS tracking.
///
/// Locked to geolocator 14.x / geolocator_android 5.x: there is NO nested
/// `androidSettings:` key on [Geolocator.getPositionStream] and no
/// `accuracyPriority:` parameter — the stream takes a single
/// `locationSettings:` argument, and on Android that argument must be an
/// [AndroidSettings] instance (it is serialized via `toJson()` and read by
/// the native plugin's `LocationOptions.parseArguments`).
///
/// Tuned for scooter rides: high accuracy, 2 m movement threshold, 500 ms
/// interval, no time limit.
AndroidSettings buildRideLocationSettings() {
  return AndroidSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 2,
    timeLimit: null,
    intervalDuration: const Duration(milliseconds: 500),
  );
}
