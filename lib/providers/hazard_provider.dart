import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/hazard_model.dart';
import '../services/location_service.dart';

class HazardProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocationService _locationService = LocationService();
  
  List<HazardModel> _hazards = [];
  Position? _currentLocation;

  // Separate Notification Logs for Hazard Alerts and Geofencing Alerts
  final List<Map<String, dynamic>> _hazardAlertsHistory = [];
  final List<Map<String, dynamic>> _geofencingAlertsHistory = [];

  // Unread badge counter state for notification icon
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  Timer? _geofenceTimer;
  StreamSubscription<QuerySnapshot>? _hazardsSubscription;
  final Set<String> _notifiedHazardIds = {};
  final Set<String> _notifiedGeofenceKeys = {};

  List<HazardModel> get hazards => _hazards;

  // Requirement 4: Map hazards filtered to show ONLY hazards created within the last 60 minutes (1 hour)
  List<HazardModel> get activeMapHazards {
    final now = DateTime.now();
    return _hazards.where((h) {
      return now.difference(h.timestamp).inMinutes < 60;
    }).toList();
  }

  Position? get currentLocation => _currentLocation;
  
  List<Map<String, dynamic>> get hazardAlertsHistory => _hazardAlertsHistory;
  List<Map<String, dynamic>> get geofencingAlertsHistory => _geofencingAlertsHistory;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Initialize and load hazards with real-time sync
  Future<void> initHazards() async {
    _isLoading = true;
    notifyListeners();

    // Set default coordinates (Karachi center) before GPS fetching
    _currentLocation = Position(
      latitude: LocationService.defaultLatitude,
      longitude: LocationService.defaultLongitude,
      timestamp: DateTime.now(),
      accuracy: 1.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );

    try {
      // Check if hazards collection is empty, seed if necessary
      final testSnapshot = await _firestore.collection('hazards').limit(1).get();
      if (testSnapshot.docs.isEmpty) {
        await _seedDefaultHazards();
      }

      // Listen to real-time updates from Firestore
      _hazardsSubscription?.cancel();
      _hazardsSubscription = _firestore
          .collection('hazards')
          .orderBy('timestamp', descending: true)
          .snapshots()
          .listen((snapshot) {
        _hazards = snapshot.docs
            .map((doc) => HazardModel.fromJson(doc.data()))
            .toList();

        _syncHazardAlertsHistory();
        _runGeofenceCheck();
        notifyListeners();
      }, onError: (error) {
        debugPrint('Error in hazards stream listener: $error');
      });

      // Attempt to get user real location
      await updateLocation();

      // Start periodic geofencing timer
      _runGeofenceCheck();
      _geofenceTimer?.cancel();
      _geofenceTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
        _runGeofenceCheck();
      });
    } catch (e) {
      debugPrint('Error initializing hazards: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Populate initial hazard notifications history with exact timestamps
  void _syncHazardAlertsHistory() {
    bool hasNew = false;
    for (var hazard in _hazards) {
      if (!_notifiedHazardIds.contains(hazard.id)) {
        _notifiedHazardIds.add(hazard.id);
        _hazardAlertsHistory.insert(0, {
          'id': hazard.id,
          'type': hazard.type,
          'message': hazard.message,
          'reportedBy': hazard.reportedBy,
          'timestamp': hazard.timestamp,
        });
        _unreadCount++;
        hasNew = true;
      }
    }
    if (hasNew) {
      notifyListeners();
    }
  }

  // Seed default Karachi hazards in Firestore
  Future<void> _seedDefaultHazards() async {
    final now = DateTime.now();
    final defaultHazards = [
      HazardModel(
        id: 'h1',
        type: 'Traffic Jam',
        latitude: 24.8698,
        longitude: 67.0658,
        message: 'Heavy traffic congestion on Shahrah-e-Faisal near Nursery flyover.',
        timestamp: now.subtract(const Duration(minutes: 15)),
        reportedBy: 'Traffic Admin',
      ),
      HazardModel(
        id: 'h2',
        type: 'Accident',
        latitude: 24.9312,
        longitude: 67.1147,
        message: 'Vehicle accident reported near NED University main gate.',
        timestamp: now.subtract(const Duration(minutes: 40)),
        reportedBy: 'Emergency Ops',
      ),
      HazardModel(
        id: 'h3',
        type: 'Rain',
        latitude: 24.8138,
        longitude: 67.0281,
        message: 'Water logging and slippery road condition near Teen Talwar, Clifton.',
        timestamp: now.subtract(const Duration(hours: 2)), // Note: Older than 1h, will stay in history but not on map!
        reportedBy: 'Met Office Admin',
      ),
    ];

    for (var hazard in defaultHazards) {
      await _firestore.collection('hazards').doc(hazard.id).set(hazard.toJson());
    }
  }

  // Force location update
  Future<void> updateLocation() async {
    final pos = await _locationService.getCurrentLocation();
    if (pos != null) {
      _currentLocation = pos;
      notifyListeners();
      _runGeofenceCheck();
    }
  }

  // Manually update location (e.g. from user navigation routes or search)
  void setManualLocation(double lat, double lon) {
    _currentLocation = Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.now(),
      accuracy: 1.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );
    notifyListeners();
    _runGeofenceCheck();
  }

  // Admin and manual User hazard reporting without image requirement
  Future<void> addHazard({
    required String type,
    required double latitude,
    required double longitude,
    required String message,
    required String reportedBy,
  }) async {
    final id = 'h_${DateTime.now().millisecondsSinceEpoch}';
    final newHazard = HazardModel(
      id: id,
      type: type,
      latitude: latitude,
      longitude: longitude,
      message: message,
      timestamp: DateTime.now(),
      reportedBy: reportedBy,
    );

    // Save to Firestore
    await _firestore.collection('hazards').doc(id).set(newHazard.toJson());
  }

  // Requirement 5: Geofencing Route Monitoring (Traffic, Rain, Weather alerts along route)
  void checkRouteGeofence(List<LatLng> routePoints, {String? weatherCondition, double? temp}) {
    if (routePoints.isEmpty) return;

    final now = DateTime.now();
    bool addedNew = false;

    // 1. Weather geofence along route
    if (weatherCondition != null) {
      final key = 'weather_${weatherCondition}_${now.hour}';
      if (!_notifiedGeofenceKeys.contains(key)) {
        _notifiedGeofenceKeys.add(key);

        String alertTitle = 'Route Weather Update';
        String alertMsg = 'Weather condition along your route is currently $weatherCondition (${temp?.toStringAsFixed(1) ?? 32}°C). Drive carefully.';
        if (weatherCondition.toLowerCase().contains('rain') || weatherCondition.toLowerCase().contains('drizzle')) {
          alertTitle = '🌧️ Rain Alert on Route';
          alertMsg = 'Precipitation detected on active route. Reduce speed and maintain safe distance.';
        }

        _geofencingAlertsHistory.insert(0, {
          'id': key,
          'category': 'Weather',
          'title': alertTitle,
          'message': alertMsg,
          'timestamp': now,
        });
        _unreadCount++;
        addedNew = true;
      }
    }

    // 2. Traffic & hazard geofencing along route
    for (var hazard in _hazards) {
      for (int i = 0; i < routePoints.length; i += mathMax(1, (routePoints.length / 10).floor())) {
        final point = routePoints[i];
        final dist = Geolocator.distanceBetween(
          hazard.latitude,
          hazard.longitude,
          point.latitude,
          point.longitude,
        );

        if (dist < 1500) { // Within 1.5 km of route point
          final geofenceKey = 'geo_${hazard.id}';
          if (!_notifiedGeofenceKeys.contains(geofenceKey)) {
            _notifiedGeofenceKeys.add(geofenceKey);

            String iconCategory = 'Traffic';
            if (hazard.type == 'Rain') iconCategory = 'Rain/Waterlogging';
            if (hazard.type == 'Accident') iconCategory = 'Accident';

            _geofencingAlertsHistory.insert(0, {
              'id': geofenceKey,
              'category': iconCategory,
              'title': '🚨 Route Alert: ${hazard.type}',
              'message': '${hazard.message} (Approx. ${(dist / 1000).toStringAsFixed(1)} km ahead on your path)',
              'timestamp': now,
            });
            _unreadCount++;
            addedNew = true;
          }
          break;
        }
      }
    }

    if (addedNew) {
      notifyListeners();
    }
  }

  int mathMax(int a, int b) => a > b ? a : b;

  // Proximity geofence check for user's immediate coordinates
  void _runGeofenceCheck() {
    if (_currentLocation == null) return;
    
    final currentLat = _currentLocation!.latitude;
    final currentLon = _currentLocation!.longitude;
    final now = DateTime.now();

    for (var hazard in _hazards) {
      final isNear = _locationService.isWithinRange(
        currentLat,
        currentLon,
        hazard.latitude,
        hazard.longitude,
        rangeInKm: 5.0,
      );

      if (isNear) {
        final geofenceKey = 'prox_${hazard.id}';
        if (!_notifiedGeofenceKeys.contains(geofenceKey)) {
          _notifiedGeofenceKeys.add(geofenceKey);

          _geofencingAlertsHistory.insert(0, {
            'id': geofenceKey,
            'category': 'Geofence Proximity',
            'title': '📍 Geofence Alert (${hazard.type})',
            'message': '${hazard.type} reported within 5km radius: "${hazard.message}"',
            'timestamp': now,
          });
          _unreadCount++;
          notifyListeners();
        }
      }
    }
  }

  // Reset unread badge counter when user views notifications
  void markNotificationsAsRead() {
    if (_unreadCount > 0) {
      _unreadCount = 0;
      notifyListeners();
    }
  }

  // Requirement 3: Clear all notifications feature
  void clearAllNotifications() {
    _hazardAlertsHistory.clear();
    _geofencingAlertsHistory.clear();
    _unreadCount = 0;
    notifyListeners();
  }

  void clearHazardNotifications() {
    _hazardAlertsHistory.clear();
    notifyListeners();
  }

  void clearGeofenceNotifications() {
    _geofencingAlertsHistory.clear();
    _notifiedGeofenceKeys.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _geofenceTimer?.cancel();
    _hazardsSubscription?.cancel();
    super.dispose();
  }
}
