import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/location_service.dart';
import '../services/routing_service.dart';
import '../services/weather_service.dart';

class GeofenceAlert {
  final String id;
  final String category;
  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final DateTime timestamp;

  GeofenceAlert({
    required this.id,
    required this.category,
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    required this.timestamp,
  });
}

class NavigationProvider extends ChangeNotifier {
  final LocationService _locationService = LocationService();
  final RoutingService _routingService = RoutingService();
  final WeatherService _weatherService = WeatherService();

  // Navigation State
  bool _isNavigating = false;
  bool get isNavigating => _isNavigating;

  bool _hasArrived = false;
  bool get hasArrived => _hasArrived;

  Position? _currentPosition;
  Position? get currentPosition => _currentPosition;

  double _liveSpeedKmH = 0.0;
  double get liveSpeedKmH => _liveSpeedKmH;

  double _currentHeading = 0.0;
  double get currentHeading => _currentHeading;

  RouteDetails? _routeDetails;
  RouteDetails? get routeDetails => _routeDetails;

  List<LatLng> _routePoints = [];
  List<LatLng> get routePoints => _routePoints;

  // Active remaining points for dynamic polyline trimming based on real GPS
  List<LatLng> _remainingRoutePoints = [];
  List<LatLng> get remainingRoutePoints => _remainingRoutePoints;

  int _currentStepIndex = 0;
  int get currentStepIndex => _currentStepIndex;

  // Remaining Distance & Time based strictly on real GPS location
  double _remainingDistanceKm = 0.0;
  double get remainingDistanceKm => _remainingDistanceKm;

  int _remainingDurationMins = 0;
  int get remainingDurationMins => _remainingDurationMins;

  String _etaString = '';
  String get etaString => _etaString;

  // Settings State
  bool _isNightMode = false;
  bool get isNightMode => _isNightMode;

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  String _travelMode = 'driving';
  String get travelMode => _travelMode;

  // Active Alerts History
  final List<GeofenceAlert> _activeGeofenceAlerts = [];
  List<GeofenceAlert> get activeGeofenceAlerts => _activeGeofenceAlerts;

  final List<WeatherAlert> _activeWeatherAlerts = [];
  List<WeatherAlert> get activeWeatherAlerts => _activeWeatherAlerts;

  // Real GPS Stream Subscription
  StreamSubscription<Position>? _positionStreamSubscription;

  // Current Destination Address
  String _currentDestination = '';

  NavigationProvider() {
    _initPositionStream();
  }

  // 1. Geolocator.getPositionStream() is the ONLY source of location updates
  void _initPositionStream() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = _locationService.getPositionStream().listen(
      (position) {
        _currentPosition = position;
        
        // 2. Speed ONLY from real GPS (m/s * 3.6)
        _liveSpeedKmH = _locationService.calculateSpeedInKmH(position);
        
        // 3. Heading ONLY from real GPS sensor
        if (position.heading >= 0) {
          _currentHeading = position.heading;
        }

        // 4. Update route progress ONLY when real GPS location updates
        if (_isNavigating && _routePoints.isNotEmpty) {
          _updateRouteProgressWithRealGPS(position);
          _checkOffRouteDeviation(position);
          _checkGeofences(position);
        }

        notifyListeners();
      },
      onError: (e) {
        debugPrint('Error in real GPS position stream: $e');
      },
    );
  }

  void setTravelMode(String mode) {
    _travelMode = mode;
    notifyListeners();
  }

  void toggleNightMode() {
    _isNightMode = !_isNightMode;
    notifyListeners();
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    notifyListeners();
  }

  void dismissArrival() {
    _hasArrived = false;
    notifyListeners();
  }

  // Fetch real Google Routes API route
  Future<void> calculateRoute(String origin, String destination) async {
    _currentDestination = destination;
    _hasArrived = false;

    try {
      final details = await _routingService.getRouteDetails(origin, destination, mode: _travelMode);
      _routeDetails = details;
      _routePoints = details.points;
      _remainingRoutePoints = List.from(details.points);
      _currentStepIndex = 0;

      _remainingDistanceKm = details.distanceValueMeters / 1000.0;
      _remainingDurationMins = (details.durationValueSeconds / 60.0).round();
      _updateETA(_remainingDurationMins);

      if (_currentPosition != null) {
        final weather = await _weatherService.fetchWeather(_currentPosition!.latitude, _currentPosition!.longitude);
        _activeWeatherAlerts.clear();
        _activeWeatherAlerts.addAll(_weatherService.evaluateWeatherAlerts(weather));
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error calculating real Google route: $e');
      rethrow;
    }
  }

  // Update route progress strictly using real GPS Position
  void _updateRouteProgressWithRealGPS(Position position) {
    if (_routePoints.isEmpty) return;

    // Check distance to destination endpoint using real GPS
    final endPoint = _routePoints.last;
    double distToEnd = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      endPoint.latitude,
      endPoint.longitude,
    );

    if (distToEnd <= 25.0) { // Arrived at destination
      _handleArrival();
      return;
    }

    // Find closest route point index relative to user's REAL GPS location
    int closestIdx = 0;
    double minDistance = double.infinity;

    for (int i = 0; i < _routePoints.length; i++) {
      double dist = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        _routePoints[i].latitude,
        _routePoints[i].longitude,
      );
      if (dist < minDistance) {
        minDistance = dist;
        closestIdx = i;
      }
    }

    _remainingRoutePoints = _routePoints.sublist(closestIdx);

    // Calculate actual remaining distance from real GPS position to end
    double remMeters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      _routePoints[closestIdx].latitude,
      _routePoints[closestIdx].longitude,
    );

    for (int i = closestIdx; i < _routePoints.length - 1; i++) {
      remMeters += Geolocator.distanceBetween(
        _routePoints[i].latitude,
        _routePoints[i].longitude,
        _routePoints[i + 1].latitude,
        _routePoints[i + 1].longitude,
      );
    }

    _remainingDistanceKm = remMeters / 1000.0;
    double speedMps = position.speed > 1.0 ? position.speed : 12.0; // use actual speed or ~43 km/h
    _remainingDurationMins = (remMeters / speedMps / 60.0).round();
    _updateETA(_remainingDurationMins);

    // Step instruction tracking
    if (_routeDetails != null && _routeDetails!.steps.isNotEmpty) {
      for (int s = 0; s < _routeDetails!.steps.length; s++) {
        final step = _routeDetails!.steps[s];
        double distToStep = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          step.endLocation.latitude,
          step.endLocation.longitude,
        );
        if (distToStep < 80 && s + 1 < _routeDetails!.steps.length) {
          _currentStepIndex = s + 1;
        }
      }
    }
  }

  void _updateETA(int mins) {
    final now = DateTime.now().add(Duration(minutes: mins));
    final hour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final amPm = now.hour >= 12 ? 'PM' : 'AM';
    final minuteStr = now.minute.toString().padLeft(2, '0');
    _etaString = '$hour:$minuteStr $amPm ($mins mins left)';
  }

  // Recalculate route automatically if user leaves route by > 30 meters
  void _checkOffRouteDeviation(Position position) {
    if (_remainingRoutePoints.isEmpty) return;

    double minDistance = double.infinity;
    for (var point in _remainingRoutePoints) {
      double dist = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        point.latitude,
        point.longitude,
      );
      if (dist < minDistance) {
        minDistance = dist;
      }
    }

    // Explicit Requirement: Recalculate if user leaves route by > 30 meters
    if (minDistance > 30.0) {
      debugPrint('User off-route (${minDistance.toStringAsFixed(1)}m away > 30m threshold). Requesting new route from Google Routes API...');
      final originStr = '${position.latitude},${position.longitude}';
      calculateRoute(originStr, _currentDestination);
    }
  }

  void _checkGeofences(Position position) {
    final now = DateTime.now();

    final presetGeofences = [
      {
        'id': 'geo_speedcam',
        'lat': 24.8698,
        'lon': 67.0658,
        'category': 'Speed Camera',
        'title': '📷 Speed Camera Ahead',
        'msg': 'Speed limit 60 km/h enforced 400m ahead on Shahrah-e-Faisal.',
        'icon': Icons.camera_alt,
        'color': Colors.redAccent,
      },
      {
        'id': 'geo_school',
        'lat': 24.9312,
        'lon': 67.1147,
        'category': 'School Zone',
        'title': '🏫 University & School Zone',
        'msg': 'Caution: Students crossing area ahead on University Road.',
        'icon': Icons.school,
        'color': Colors.orangeAccent,
      },
      {
        'id': 'geo_hospital',
        'lat': 24.8624,
        'lon': 67.0298,
        'category': 'Hospital Zone',
        'title': '🏥 Hospital Zone - Quiet Area',
        'msg': 'Hospital zone ahead. Avoid honking.',
        'icon': Icons.local_hospital,
        'color': Colors.blueAccent,
      },
      {
        'id': 'geo_sharpturn',
        'lat': 24.8138,
        'lon': 67.0281,
        'category': 'Sharp Turn',
        'title': '↩️ Sharp Turn Ahead',
        'msg': 'Sharp curve ahead near Clifton roundabout. Reduce speed.',
        'icon': Icons.turn_sharp_right,
        'color': Colors.purpleAccent,
      },
    ];

    for (var g in presetGeofences) {
      double dist = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        g['lat'] as double,
        g['lon'] as double,
      );

      if (dist < 1000) {
        final id = g['id'] as String;
        if (!_activeGeofenceAlerts.any((a) => a.id == id)) {
          _activeGeofenceAlerts.insert(
            0,
            GeofenceAlert(
              id: id,
              category: g['category'] as String,
              title: g['title'] as String,
              message: g['msg'] as String,
              icon: g['icon'] as IconData,
              color: g['color'] as Color,
              timestamp: now,
            ),
          );
        }
      }
    }
  }

  // Real GPS Navigation Start: Sets navigating flag. NO TIMERS OR SIMULATED MOVEMENTS!
  void startNavigation() {
    if (_routePoints.isEmpty) return;

    _isNavigating = true;
    _hasArrived = false;
    _currentStepIndex = 0;
    _remainingRoutePoints = List.from(_routePoints);

    notifyListeners();
  }

  void _handleArrival() {
    stopNavigation();
    _hasArrived = true;
    _routeDetails = null;
    _routePoints = [];
    _remainingRoutePoints = [];
    notifyListeners();
  }

  void stopNavigation() {
    _isNavigating = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }
}
