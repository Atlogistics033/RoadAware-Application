import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class PlacePrediction {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  PlacePrediction({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });

  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    final struct = json['structured_formatting'] ?? {};
    return PlacePrediction(
      placeId: json['place_id'] ?? '',
      description: json['description'] ?? '',
      mainText: struct['main_text'] ?? json['description'] ?? '',
      secondaryText: struct['secondary_text'] ?? '',
    );
  }
}

class PlaceDetails {
  final String placeId;
  final String name;
  final String formattedAddress;
  final LatLng location;

  PlaceDetails({
    required this.placeId,
    required this.name,
    required this.formattedAddress,
    required this.location,
  });
}

class PlacesService {
  static const String apiKey = 'AIzaSyD-u2usnp7ZjU_YeufNdV2j40szwvPWx_0';

  // Get autocomplete predictions from Google Places Autocomplete API
  Future<List<PlacePrediction>> getAutocompletePredictions(String query, {double? lat, double? lon}) async {
    if (query.trim().length < 2) return [];

    String locationParam = '';
    if (lat != null && lon != null) {
      locationParam = '&location=$lat,$lon&radius=50000';
    }

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json'
      '?input=${Uri.encodeComponent(query)}'
      '&key=$apiKey'
      '$locationParam'
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'OK' && data['predictions'] != null) {
          return (data['predictions'] as List)
              .map((p) => PlacePrediction.fromJson(p))
              .toList();
        }
      }
      return _generateFallbackPredictions(query);
    } catch (e) {
      debugPrint('Places Autocomplete network exception, using smart fallback: $e');
      return _generateFallbackPredictions(query);
    }
  }

  // Get place details (coordinates) from Place ID
  Future<PlaceDetails?> getPlaceDetails(String placeId, String fallbackName) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json'
      '?place_id=$placeId'
      '&fields=name,formatted_address,geometry'
      '&key=$apiKey'
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'OK' && data['result'] != null) {
          final res = data['result'];
          final location = res['geometry']['location'];
          return PlaceDetails(
            placeId: placeId,
            name: res['name'] ?? fallbackName,
            formattedAddress: res['formatted_address'] ?? fallbackName,
            location: LatLng(
              (location['lat'] as num).toDouble(),
              (location['lng'] as num).toDouble(),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Place Details API error: $e');
    }

    // Fallback coordinates for key Karachi locations if place details API returns fallback
    return _resolveFallbackPlaceDetails(fallbackName);
  }

  List<PlacePrediction> _generateFallbackPredictions(String query) {
    final q = query.toLowerCase();
    List<PlacePrediction> list = [];

    if ('clifton teen talwar'.contains(q) || q.contains('clif')) {
      list.add(PlacePrediction(
        placeId: 'p_clifton',
        description: 'Teen Talwar, Clifton, Karachi, Pakistan',
        mainText: 'Teen Talwar, Clifton',
        secondaryText: 'Karachi, Pakistan',
      ));
    }
    if ('ned university road'.contains(q) || q.contains('ned') || q.contains('univ')) {
      list.add(PlacePrediction(
        placeId: 'p_ned',
        description: 'NED University of Engineering & Technology, Main University Rd, Karachi',
        mainText: 'NED University of Engineering & Technology',
        secondaryText: 'Main University Rd, Karachi',
      ));
    }
    if ('gulshan-e-iqbal'.contains(q) || q.contains('gul') || q.contains('iqb')) {
      list.add(PlacePrediction(
        placeId: 'p_gulshan',
        description: 'Gulshan-e-Iqbal, Karachi, Pakistan',
        mainText: 'Gulshan-e-Iqbal',
        secondaryText: 'Karachi, Pakistan',
      ));
    }
    if ('jinnah international airport'.contains(q) || q.contains('air') || q.contains('jin')) {
      list.add(PlacePrediction(
        placeId: 'p_airport',
        description: 'Jinnah International Airport, Airport Road, Karachi',
        mainText: 'Jinnah International Airport',
        secondaryText: 'Airport Road, Karachi',
      ));
    }
    if ('saddar empress market'.contains(q) || q.contains('sad') || q.contains('emp')) {
      list.add(PlacePrediction(
        placeId: 'p_saddar',
        description: 'Empress Market, Saddar, Karachi, Pakistan',
        mainText: 'Empress Market, Saddar',
        secondaryText: 'Karachi, Pakistan',
      ));
    }

    if (list.isEmpty) {
      list.add(PlacePrediction(
        placeId: 'p_custom',
        description: '$query, Karachi, Pakistan',
        mainText: query,
        secondaryText: 'Karachi, Pakistan',
      ));
    }
    return list;
  }

  PlaceDetails _resolveFallbackPlaceDetails(String name) {
    final lower = name.toLowerCase();
    LatLng pos = const LatLng(24.8607, 67.0011);

    if (lower.contains('clifton') || lower.contains('teen talwar')) {
      pos = const LatLng(24.8138, 67.0281);
    } else if (lower.contains('ned') || lower.contains('university')) {
      pos = const LatLng(24.9312, 67.1147);
    } else if (lower.contains('gulshan') || lower.contains('iqbal')) {
      pos = const LatLng(24.9180, 67.0970);
    } else if (lower.contains('airport')) {
      pos = const LatLng(24.9065, 67.1608);
    } else if (lower.contains('saddar') || lower.contains('empress')) {
      pos = const LatLng(24.8624, 67.0298);
    } else if (lower.contains('tariq')) {
      pos = const LatLng(24.8719, 67.0583);
    } else if (lower.contains('nursery') || lower.contains('shahrah')) {
      pos = const LatLng(24.8698, 67.0658);
    }

    return PlaceDetails(
      placeId: 'p_fallback',
      name: name,
      formattedAddress: '$name, Karachi',
      location: pos,
    );
  }
}
