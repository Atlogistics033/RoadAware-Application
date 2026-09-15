import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  // Karachi city default center coordinates
  static const double defaultLatitude = 24.8607;
  static const double defaultLongitude = 67.0011;

  Future<Position?> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      debugPrint('Error getting location: $e');
      return null;
    }
  }

  // Requirement 1 & 18: Real-Time Live GPS Location Stream
  Stream<Position> getPositionStream() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 2, // Emit update when user moves by 2 meters
    );

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  // Calculate speed in km/h from Geolocator speed (m/s)
  double calculateSpeedInKmH(Position position) {
    if (position.speed < 0) return 0.0;
    return position.speed * 3.6;
  }

  // Calculate distance between two coordinates in meters
  double calculateDistance(double startLat, double startLon, double endLat, double endLon) {
    return Geolocator.distanceBetween(startLat, startLon, endLat, endLon);
  }

  // Check if coordinate is within range (in km)
  bool isWithinRange(double startLat, double startLon, double endLat, double endLon, {double rangeInKm = 5.0}) {
    final distanceInMeters = calculateDistance(startLat, startLon, endLat, endLon);
    return distanceInMeters <= (rangeInKm * 1000.0);
  }
}
