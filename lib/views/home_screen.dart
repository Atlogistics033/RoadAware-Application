import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../providers/auth_provider.dart';
import '../providers/hazard_provider.dart';
import '../providers/weather_provider.dart';
import '../providers/navigation_provider.dart';
import '../services/places_service.dart';
import '../utils/theme.dart';
import '../utils/constants.dart';
import '../models/hazard_model.dart';
import 'admin_panel_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GoogleMapController? _mapController;
  final TextEditingController _sourceController = TextEditingController(text: 'My Location (Shahrah-e-Faisal)');
  final TextEditingController _destController = TextEditingController();

  final PlacesService _placesService = PlacesService();
  List<PlacePrediction> _autocompletePredictions = [];
  bool _isSearchingPredictions = false;
  bool _isSearchingRoute = false;

  static const LatLng _karachiCenter = LatLng(AppConstants.defaultLat, AppConstants.defaultLng);

  // Dark Map Style JSON string for Night Mode
  static const String _darkMapStyle = '''[
    {"elementType": "geometry", "stylers": [{"color": "#242f3e"}]},
    {"elementType": "labels.text.fill", "stylers": [{"color": "#746855"}]},
    {"elementType": "labels.text.stroke", "stylers": [{"color": "#242f3e"}]},
    {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#d59563"}]},
    {"featureType": "poi", "elementType": "labels.text.fill", "stylers": [{"color": "#d59563"}]},
    {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#38414e"}]},
    {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#212a37"}]},
    {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#9ca5b3"}]},
    {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#746855"}]},
    {"featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{"color": "#1f2835"}]},
    {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#17263c"}]}
  ]''';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final hazardProv = Provider.of<HazardProvider>(context, listen: false);
      final lat = hazardProv.currentLocation?.latitude ?? AppConstants.defaultLat;
      final lon = hazardProv.currentLocation?.longitude ?? AppConstants.defaultLng;
      Provider.of<WeatherProvider>(context, listen: false).loadWeather(lat, lon);
    });
  }

  @override
  void dispose() {
    _sourceController.dispose();
    _destController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _onDestinationTextChanged(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _autocompletePredictions = [];
        _isSearchingPredictions = false;
      });
      return;
    }

    setState(() {
      _isSearchingPredictions = true;
    });

    final hazardProv = Provider.of<HazardProvider>(context, listen: false);
    double? lat = hazardProv.currentLocation?.latitude;
    double? lon = hazardProv.currentLocation?.longitude;

    final predictions = await _placesService.getAutocompletePredictions(query, lat: lat, lon: lon);

    if (mounted) {
      setState(() {
        _autocompletePredictions = predictions;
        _isSearchingPredictions = false;
      });
    }
  }

  void _selectPrediction(PlacePrediction prediction) async {
    _destController.text = prediction.mainText;
    setState(() {
      _autocompletePredictions = [];
    });

    FocusScope.of(context).unfocus();
    await _searchAndDrawRoute(prediction.description);
  }

  Future<void> _searchAndDrawRoute(String destination) async {
    if (destination.trim().isEmpty) return;

    final navProv = Provider.of<NavigationProvider>(context, listen: false);
    final hazardProv = Provider.of<HazardProvider>(context, listen: false);

    String startLoc = _sourceController.text.trim();
    if (startLoc == 'My Location (Shahrah-e-Faisal)' && hazardProv.currentLocation != null) {
      startLoc = '${hazardProv.currentLocation!.latitude},${hazardProv.currentLocation!.longitude}';
    }

    setState(() {
      _isSearchingRoute = true;
    });

    try {
      await navProv.calculateRoute(startLoc, destination);

      if (mounted && navProv.routeDetails != null) {
        // Fit camera to complete route bounds upon route generation
        try {
          _mapController?.animateCamera(
            CameraUpdate.newLatLngBounds(navProv.routeDetails!.bounds, 50.0),
          );
        } catch (_) {
          if (navProv.routePoints.isNotEmpty) {
            final start = navProv.routePoints.first;
            final end = navProv.routePoints.last;
            _mapController?.animateCamera(
              CameraUpdate.newLatLngZoom(
                LatLng((start.latitude + end.latitude) / 2, (start.longitude + end.longitude) / 2),
                13.0,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to calculate route: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingRoute = false;
        });
      }
    }
  }

  void _clearRoute() {
    final navProv = Provider.of<NavigationProvider>(context, listen: false);
    navProv.stopNavigation();
    _destController.clear();
    setState(() {
      _autocompletePredictions = [];
    });
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_karachiCenter, 12));
  }

  BitmapDescriptor _getMarkerColor(String type) {
    switch (type) {
      case 'Traffic Jam':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
      case 'Accident':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      case 'Rain':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
      case 'Pothole':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
      default:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
    }
  }

  // Build Markers: Marker strictly represents real GPS location!
  Set<Marker> _buildMarkers(List<HazardModel> activeHazards, NavigationProvider navProv, HazardProvider hazardProv) {
    final Set<Marker> markers = {};

    LatLng pos = _karachiCenter;
    if (navProv.currentPosition != null) {
      pos = LatLng(navProv.currentPosition!.latitude, navProv.currentPosition!.longitude);
    } else if (hazardProv.currentLocation != null) {
      pos = LatLng(hazardProv.currentLocation!.latitude, hazardProv.currentLocation!.longitude);
    }

    // Real user position blue marker
    markers.add(
      Marker(
        markerId: const MarkerId('current_location'),
        position: pos,
        infoWindow: const InfoWindow(title: 'My Current Location'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
    );

    // Destination marker
    if (navProv.routePoints.isNotEmpty) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination_location'),
          position: navProv.routePoints.last,
          infoWindow: InfoWindow(title: _destController.text.isNotEmpty ? _destController.text : 'Destination'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }

    for (var hazard in activeHazards) {
      markers.add(
        Marker(
          markerId: MarkerId(hazard.id),
          position: LatLng(hazard.latitude, hazard.longitude),
          infoWindow: InfoWindow(
            title: '${hazard.type} (${_formatTime(hazard.timestamp)})',
            snippet: hazard.message,
          ),
          icon: _getMarkerColor(hazard.type),
          onTap: () => _showHazardDetailDialog(context, hazard),
        ),
      );
    }
    return markers;
  }

  Set<Polyline> _buildPolylines(NavigationProvider navProv) {
    if (navProv.routeDetails == null) return {};

    List<LatLng> pointsToDraw = navProv.isNavigating && navProv.remainingRoutePoints.isNotEmpty
        ? navProv.remainingRoutePoints
        : navProv.routePoints;

    return {
      Polyline(
        polylineId: const PolylineId('active_decoded_route'),
        color: AppTheme.primaryBlue,
        width: 7,
        points: pointsToDraw,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    };
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final day = dt.day;
    final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '$hour:$min - $day ${monthNames[dt.month - 1]}';
  }

  void _showHazardDetailDialog(BuildContext context, HazardModel hazard) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(
                hazard.type == 'Accident'
                    ? Icons.car_crash
                    : hazard.type == 'Traffic Jam'
                        ? Icons.traffic
                        : Icons.warning_amber_rounded,
                color: AppTheme.primaryBlue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hazard.type,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reported By: ${hazard.reportedBy}',
                style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Time: ${_formatTime(hazard.timestamp)}',
                style: const TextStyle(fontSize: 12, color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
              ),
              const Divider(height: 20),
              Text(
                hazard.message,
                style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: AppTheme.primaryBlue)),
            ),
          ],
        );
      },
    );
  }

  void _showNotifications(BuildContext context) {
    Provider.of<HazardProvider>(context, listen: false).markNotificationsAsRead();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return DefaultTabController(
          length: 2,
          child: Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Notification Alert Center',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Provider.of<HazardProvider>(context, listen: false).clearAllNotifications();
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('All notifications cleared.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                      label: const Text('Clear All', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                Container(
                  height: 45,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: TabBar(
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: AppTheme.primaryBlue,
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.grey.shade700,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    tabs: const [
                      Tab(text: 'Hazard Alerts'),
                      Tab(text: 'Geofencing Alerts'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Expanded(
                  child: TabBarView(
                    children: [
                      Consumer<HazardProvider>(
                        builder: (context, hazardProv, _) {
                          final history = hazardProv.hazardAlertsHistory;
                          if (history.isEmpty) {
                            return _buildEmptyNotificationState('No hazard alerts reported yet.');
                          }
                          return ListView.builder(
                            itemCount: history.length,
                            itemBuilder: (context, index) {
                              final item = history[index];
                              final dt = item['timestamp'] as DateTime;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(color: Colors.red.shade100),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '⚠️ ${item['type']}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: Colors.red.shade900,
                                          ),
                                        ),
                                        Text(
                                          _formatTime(dt),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.red.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      item['message'],
                                      style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.3),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Reported by ${item['reportedBy']}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),

                      Consumer<HazardProvider>(
                        builder: (context, hazardProv, _) {
                          final geoHistory = hazardProv.geofencingAlertsHistory;
                          if (geoHistory.isEmpty) {
                            return _buildEmptyNotificationState('No active geofence or route warnings.');
                          }
                          return ListView.builder(
                            itemCount: geoHistory.length,
                            itemBuilder: (context, index) {
                              final item = geoHistory[index];
                              final dt = item['timestamp'] as DateTime;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(color: Colors.orange.shade200),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          item['title'],
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Colors.black,
                                          ),
                                        ),
                                        Text(
                                          _formatTime(dt),
                                          style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      item['message'],
                                      style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.3),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyNotificationState(String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none_outlined, size: 55, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  void _openReportHazardSheet() {
    final msgController = TextEditingController();
    double customLat = AppConstants.defaultLat;
    double customLng = AppConstants.defaultLng;

    final hazardProv = Provider.of<HazardProvider>(context, listen: false);
    if (hazardProv.currentLocation != null) {
      customLat = hazardProv.currentLocation!.latitude;
      customLng = hazardProv.currentLocation!.longitude;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        String selectedType = 'Traffic Jam';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Report Road Hazard',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedType,
                      decoration: const InputDecoration(labelText: 'Hazard Category'),
                      items: <String>['Traffic Jam', 'Road Condition', 'Accident', 'Rain', 'Pothole']
                          .map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setSheetState(() {
                            selectedType = newValue;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: msgController,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.black),
                      decoration: const InputDecoration(
                        labelText: 'Describe the road condition',
                        hintText: 'e.g. Flooded street, broken signal, or heavy blockage...',
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        gradient: AppTheme.primaryGradient,
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          if (msgController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter a brief description')),
                            );
                            return;
                          }

                          final auth = Provider.of<AuthProvider>(context, listen: false);
                          Provider.of<HazardProvider>(context, listen: false).addHazard(
                            type: selectedType,
                            latitude: customLat + (0.004 * (DateTime.now().second % 3 == 0 ? 1 : -1)),
                            longitude: customLng + (0.004 * (DateTime.now().second % 2 == 0 ? 1 : -1)),
                            message: msgController.text.trim(),
                            reportedBy: auth.currentUser?.fullName ?? 'Commuter',
                          );

                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Hazard alert reported successfully!'),
                              backgroundColor: Colors.green,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                        ),
                        child: const Text('Submit Hazard Alert'),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProv = Provider.of<AuthProvider>(context);
    final hazardProv = Provider.of<HazardProvider>(context);
    final navProv = Provider.of<NavigationProvider>(context);

    final markers = _buildMarkers(hazardProv.activeMapHazards, navProv, hazardProv);
    final polylines = _buildPolylines(navProv);

    // Smoothly animate camera ONLY when user's REAL GPS location updates during active navigation
    if (navProv.isNavigating && navProv.currentPosition != null) {
      final realGpsPos = LatLng(
        navProv.currentPosition!.latitude,
        navProv.currentPosition!.longitude,
      );
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: realGpsPos,
            zoom: 18.0,
            tilt: 60.0,
            bearing: navProv.currentHeading,
          ),
        ),
      );
    }

    return Scaffold(
      drawer: Drawer(
        backgroundColor: Colors.white,
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(
                gradient: AppTheme.primaryGradient,
              ),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                backgroundImage: authProv.currentUser?.profilePicture != null && authProv.currentUser!.profilePicture!.isNotEmpty
                    ? MemoryImage(base64Decode(authProv.currentUser!.profilePicture!))
                    : null,
                child: authProv.currentUser?.profilePicture != null && authProv.currentUser!.profilePicture!.isNotEmpty
                    ? null
                    : Text(
                        authProv.currentUser?.fullName.isNotEmpty == true
                            ? authProv.currentUser!.fullName[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                      ),
              ),
              accountName: Text(
                authProv.currentUser?.fullName ?? 'RoadAware Commuter',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              accountEmail: Text(authProv.currentUser?.emailOrPhone ?? ''),
            ),
            ListTile(
              leading: const Icon(Icons.map_outlined, color: AppTheme.primaryBlue),
              title: const Text('Home Navigation Dashboard', style: TextStyle(color: Colors.black)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline, color: AppTheme.primaryBlue),
              title: const Text('My Profile', style: TextStyle(color: Colors.black)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.report_problem_outlined, color: AppTheme.primaryBlue),
              title: const Text('Report Road Hazard', style: TextStyle(color: Colors.black)),
              onTap: () {
                Navigator.pop(context);
                _openReportHazardSheet();
              },
            ),
            if (authProv.currentUser?.isAdmin == true) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined, color: Colors.orange),
                title: const Text('Admin Panel', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                subtitle: const Text('Broadcast official road alerts'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AdminPanelScreen()),
                  );
                },
              ),
            ],
            const Spacer(),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                await authProv.logout();
                if (context.mounted) {
                  Navigator.pushReplacementNamed(context, '/login');
                }
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      body: Stack(
        children: [
          // 1. GOOGLE MAP CANVAS
          GoogleMap(
            initialCameraPosition: const CameraPosition(target: _karachiCenter, zoom: 12.0),
            onMapCreated: (controller) {
              _mapController = controller;
            },
            style: navProv.isNightMode ? _darkMapStyle : null,
            markers: markers,
            polylines: polylines,
            trafficEnabled: true,
            compassEnabled: true,
            buildingsEnabled: true,
            indoorViewEnabled: true,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),

          // 2. TOP GRADIENT COVER
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white, Colors.white.withValues(alpha: 0.9), Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

          // 3. TOP APP BAR & BRANDING
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  Builder(
                    builder: (context) {
                      return CircleAvatar(
                        backgroundColor: Colors.white,
                        child: IconButton(
                          icon: const Icon(Icons.menu, color: AppTheme.primaryBlue),
                          onPressed: () => Scaffold.of(context).openDrawer(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ROAD AWARE',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  CircleAvatar(
                    backgroundColor: navProv.isNightMode ? Colors.amber : Colors.white,
                    child: IconButton(
                      icon: Icon(
                        navProv.isNightMode ? Icons.wb_sunny : Icons.nightlight_round,
                        color: navProv.isNightMode ? Colors.black : AppTheme.primaryBlue,
                        size: 20,
                      ),
                      tooltip: 'Toggle Night Mode Map',
                      onPressed: () => navProv.toggleNightMode(),
                    ),
                  ),
                  const SizedBox(width: 8),

                  Stack(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.white,
                        child: IconButton(
                          icon: const Icon(Icons.notifications_active_outlined, color: AppTheme.primaryBlue),
                          onPressed: () => _showNotifications(context),
                        ),
                      ),
                      if (hazardProv.unreadCount > 0)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: CircleAvatar(
                            radius: 9,
                            backgroundColor: Colors.redAccent,
                            child: Text(
                              hazardProv.unreadCount.toString(),
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 4. NAVIGATION TOP BANNER & REAL SPEEDOMETER
          if (navProv.isNavigating && navProv.routeDetails != null && navProv.routeDetails!.steps.isNotEmpty)
            Positioned(
              top: 100,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: AppTheme.intenseShadow,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Colors.white24,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        navProv.routeDetails!.steps[navProv.currentStepIndex].maneuver.contains('right')
                            ? Icons.turn_right
                            : navProv.routeDetails!.steps[navProv.currentStepIndex].maneuver.contains('left')
                                ? Icons.turn_left
                                : Icons.arrow_upward,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            navProv.routeDetails!.steps[navProv.currentStepIndex].instruction,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${navProv.remainingDistanceKm.toStringAsFixed(1)} km left • ${navProv.etaString}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),

                    // Live Real Speedometer Badge (km/h) from GPS
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            navProv.liveSpeedKmH.toStringAsFixed(0),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.primaryBlue,
                            ),
                          ),
                          const Text(
                            'KM/H',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 5. DESTINATION ARRIVAL OVERLAY CARD
          if (navProv.hasArrived)
            Positioned(
              top: 110,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.shade600,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: AppTheme.intenseShadow,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Colors.white, size: 40),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'You Have Arrived!',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'You have reached your destination successfully.',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => navProv.dismissArrival(),
                    ),
                  ],
                ),
              ),
            ),

          // 6. BOTTOM GOOGLE MAPS STYLE CONTROL SHEET
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.primaryBlue,
                  onPressed: () async {
                    await hazardProv.updateLocation();
                    if (navProv.currentPosition != null) {
                      _mapController?.animateCamera(
                        CameraUpdate.newLatLngZoom(
                          LatLng(navProv.currentPosition!.latitude, navProv.currentPosition!.longitude),
                          16.0,
                        ),
                      );
                    }
                  },
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 10),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.circle_outlined, color: Colors.green, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _sourceController,
                              style: const TextStyle(color: Colors.black),
                              decoration: const InputDecoration(
                                hintText: 'Enter start location',
                                contentPadding: EdgeInsets.zero,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 10),
                      
                      Row(
                        children: [
                          const Icon(Icons.location_on, color: Colors.red, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _destController,
                              style: const TextStyle(color: Colors.black),
                              decoration: const InputDecoration(
                                hintText: 'Search destination (Google Places)...',
                                contentPadding: EdgeInsets.zero,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                              onChanged: _onDestinationTextChanged,
                              onSubmitted: (val) => _searchAndDrawRoute(val),
                            ),
                          ),
                          if (_destController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.grey, size: 18),
                              onPressed: _clearRoute,
                            ),
                        ],
                      ),

                      if (_isSearchingPredictions)
                        const LinearProgressIndicator(color: AppTheme.primaryBlue, minHeight: 2),
                      if (_autocompletePredictions.isNotEmpty)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _autocompletePredictions.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final p = _autocompletePredictions[index];
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.place_outlined, color: AppTheme.primaryBlue, size: 18),
                                title: Text(p.mainText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black)),
                                subtitle: Text(p.secondaryText, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                onTap: () => _selectPrediction(p),
                              );
                            },
                          ),
                        ),

                      if (navProv.routeDetails != null) ...[
                        const Divider(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                ChoiceChip(
                                  label: const Row(children: [Icon(Icons.directions_car, size: 16), SizedBox(width: 4), Text('Car')]),
                                  selected: navProv.travelMode == 'driving',
                                  selectedColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
                                  onSelected: (val) {
                                    if (val) {
                                      navProv.setTravelMode('driving');
                                      _searchAndDrawRoute(_destController.text);
                                    }
                                  },
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: const Row(children: [Icon(Icons.two_wheeler, size: 16), SizedBox(width: 4), Text('Bike')]),
                                  selected: navProv.travelMode == 'bicycling',
                                  selectedColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
                                  onSelected: (val) {
                                    if (val) {
                                      navProv.setTravelMode('bicycling');
                                      _searchAndDrawRoute(_destController.text);
                                    }
                                  },
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${navProv.remainingDistanceKm.toStringAsFixed(1)} km • ${navProv.etaString}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black),
                                ),
                                const Text('🟢 Google Route Ready', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isSearchingRoute ? null : () => _searchAndDrawRoute(_destController.text),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryBlue,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: _isSearchingRoute
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.search, color: Colors.white, size: 18),
                              label: Text(_isSearchingRoute ? 'Searching...' : 'Show Route', style: const TextStyle(color: Colors.white)),
                            ),
                          ),
                          if (navProv.routeDetails != null) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () => navProv.toggleMute(),
                              icon: Icon(navProv.isMuted ? Icons.volume_off : Icons.volume_up, color: AppTheme.primaryBlue),
                              tooltip: 'Mute/Unmute Audio Guidance',
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: navProv.isNavigating ? () => navProv.stopNavigation() : () => navProv.startNavigation(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: navProv.isNavigating ? Colors.redAccent : Colors.green,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: Icon(navProv.isNavigating ? Icons.stop : Icons.navigation, color: Colors.white, size: 18),
                                label: Text(
                                  navProv.isNavigating ? 'Stop' : 'Start Nav',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
