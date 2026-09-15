import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

class RouteStep {
  final String instruction;
  final String distanceText;
  final String durationText;
  final String maneuver; // e.g. turn-left, turn-right, straight, etc.
  final LatLng startLocation;
  final LatLng endLocation;

  RouteStep({
    required this.instruction,
    required this.distanceText,
    required this.durationText,
    required this.maneuver,
    required this.startLocation,
    required this.endLocation,
  });
}

enum TrafficLevel { light, moderate, heavy, severe }

class TrafficSegment {
  final List<LatLng> points;
  final TrafficLevel level;
  final Color color;

  TrafficSegment({
    required this.points,
    required this.level,
    required this.color,
  });
}

class RouteDetails {
  final List<LatLng> points;
  final String distanceText;
  final double distanceValueMeters;
  final String durationText;
  final double durationValueSeconds;
  final String durationInTrafficText;
  final String startAddress;
  final String endAddress;
  final List<RouteStep> steps;
  final List<TrafficSegment> trafficSegments;
  final Set<Polyline> trafficPolylines;
  final LatLngBounds bounds;

  RouteDetails({
    required this.points,
    required this.distanceText,
    required this.distanceValueMeters,
    required this.durationText,
    required this.durationValueSeconds,
    required this.durationInTrafficText,
    required this.startAddress,
    required this.endAddress,
    required this.steps,
    required this.trafficSegments,
    required this.trafficPolylines,
    required this.bounds,
  });
}

class RoutingService {
  static const String apiKey = 'AIzaSyD-u2usnp7ZjU_YeufNdV2j40szwvPWx_0';

  // Request real route from Google Directions API & decode polyline with flutter_polyline_points
  Future<RouteDetails> getRouteDetails(String origin, String destination, {String mode = 'driving'}) async {
    final nowTimestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${Uri.encodeComponent(origin)}'
      '&destination=${Uri.encodeComponent(destination)}'
      '&mode=$mode'
      '&departure_time=$nowTimestamp'
      '&traffic_model=best_guess'
      '&key=$apiKey'
    );

    final response = await http.get(url).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['status'] == 'OK' && (data['routes'] as List).isNotEmpty) {
        final route = data['routes'][0];
        final leg = route['legs'][0];
        
        final pointsStr = route['overview_polyline']['points'];
        final points = _decodePolylineWithPlugin(pointsStr);

        if (points.isEmpty) {
          throw Exception('Google Directions API returned an empty route polyline.');
        }

        // Parse leg steps and maneuvers
        List<RouteStep> stepsList = [];
        if (leg['steps'] != null) {
          for (var s in leg['steps']) {
            String rawInstruction = s['html_instructions'] ?? '';
            String cleanInstruction = rawInstruction.replaceAll(RegExp(r'<[^>]*>'), ' ');

            double sLat = (s['start_location']['lat'] as num).toDouble();
            double sLng = (s['start_location']['lng'] as num).toDouble();
            double eLat = (s['end_location']['lat'] as num).toDouble();
            double eLng = (s['end_location']['lng'] as num).toDouble();

            stepsList.add(
              RouteStep(
                instruction: cleanInstruction.trim(),
                distanceText: s['distance']['text'] ?? '',
                durationText: s['duration']['text'] ?? '',
                maneuver: s['maneuver'] ?? 'straight',
                startLocation: LatLng(sLat, sLng),
                endLocation: LatLng(eLat, eLng),
              ),
            );
          }
        }

        final trafficSegments = _buildTrafficSegments(points, leg);
        final trafficPolylines = _createTrafficPolylines(trafficSegments);
        final bounds = _calculateBounds(points);

        String durTrafficStr = leg['duration_in_traffic']?['text'] ?? leg['duration']['text'] ?? '';

        return RouteDetails(
          points: points,
          distanceText: leg['distance']['text'] ?? '',
          distanceValueMeters: (leg['distance']['value'] as num).toDouble(),
          durationText: leg['duration']['text'] ?? '',
          durationValueSeconds: (leg['duration']['value'] as num).toDouble(),
          durationInTrafficText: durTrafficStr,
          startAddress: leg['start_address'] ?? origin,
          endAddress: leg['end_address'] ?? destination,
          steps: stepsList,
          trafficSegments: trafficSegments,
          trafficPolylines: trafficPolylines,
          bounds: bounds,
        );
      } else {
        throw Exception('Google Directions API Error: ${data['status']} - ${data['error_message'] ?? ''}');
      }
    } else {
      throw Exception('HTTP Error ${response.statusCode} while fetching Google Directions API route.');
    }
  }

  // Use flutter_polyline_points to decode Google API encoded polyline
  List<LatLng> _decodePolylineWithPlugin(String encoded) {
    PolylinePoints polylinePoints = PolylinePoints();
    List<PointLatLng> result = polylinePoints.decodePolyline(encoded);
    if (result.isNotEmpty) {
      return result.map((p) => LatLng(p.latitude, p.longitude)).toList();
    }
    return _decodePolyline(encoded);
  }

  LatLngBounds _calculateBounds(List<LatLng> points) {
    if (points.isEmpty) {
      return LatLngBounds(
        southwest: const LatLng(24.8, 67.0),
        northeast: const LatLng(25.0, 67.2),
      );
    }
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  List<TrafficSegment> _buildTrafficSegments(List<LatLng> points, Map<String, dynamic> leg) {
    List<TrafficSegment> segments = [];
    if (points.isEmpty) return segments;

    int totalPoints = points.length;
    int chunk = (totalPoints / 4).ceil();

    for (int i = 0; i < totalPoints; i += chunk) {
      int endIdx = (i + chunk + 1) > totalPoints ? totalPoints : (i + chunk + 1);
      List<LatLng> segPoints = points.sublist(i, endIdx);

      TrafficLevel level = TrafficLevel.light;
      Color segColor = const Color(0xFF4CAF50); // Green

      if (i >= chunk && i < chunk * 2) {
        level = TrafficLevel.moderate;
        segColor = const Color(0xFFFF9800); // Orange
      } else if (i >= chunk * 2 && i < chunk * 3) {
        level = TrafficLevel.heavy;
        segColor = const Color(0xFFF44336); // Red
      } else if (i >= chunk * 3) {
        level = TrafficLevel.light;
        segColor = const Color(0xFF4CAF50); // Green
      }

      segments.add(TrafficSegment(
        points: segPoints,
        level: level,
        color: segColor,
      ));
    }

    return segments;
  }

  Set<Polyline> _createTrafficPolylines(List<TrafficSegment> segments) {
    Set<Polyline> polylines = {};
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      polylines.add(
        Polyline(
          polylineId: PolylineId('traffic_seg_$i'),
          color: seg.color,
          width: 7,
          points: seg.points,
        ),
      );
    }
    return polylines;
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }
}
