import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  static Future<bool> requestPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[LocationService] Location services (GPS) are disabled on the device.');
      return false;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.deniedForever) {
      debugPrint('[LocationService] Location permissions are permanently denied.');
      return false;
    }

    final granted = perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
    debugPrint('[LocationService] Permission status: $perm (granted: $granted)');
    return granted;
  }

  static Future<Position?> getCurrentPosition() async {
    final ok = await requestPermission();
    if (!ok) {
      debugPrint('[LocationService] Permission check failed or GPS disabled');
      return null;
    }

    try {
      debugPrint('[LocationService] Requesting fresh GPS position (accuracy: best)...');
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );
      debugPrint('[LocationService] Fresh GPS fix obtained: lat=${pos.latitude}, lng=${pos.longitude}, accuracy=${pos.accuracy}m');
      return pos;
    } catch (e) {
      debugPrint('[LocationService] Error getting fresh position: $e. Checking last known position...');
      try {
        final lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null) {
          debugPrint('[LocationService] Using last known GPS position: lat=${lastPos.latitude}, lng=${lastPos.longitude}, accuracy=${lastPos.accuracy}m');
          return lastPos;
        }
      } catch (_) {}
      return null;
    }
  }

  static Stream<Position> positionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
      ),
    );
  }
}

