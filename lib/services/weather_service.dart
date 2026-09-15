import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherData {
  final double temp;
  final String condition;
  final String description;
  final int humidity;
  final double windSpeed; // m/s
  final int visibility;   // meters

  WeatherData({
    required this.temp,
    required this.condition,
    required this.description,
    required this.humidity,
    required this.windSpeed,
    required this.visibility,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final main = json['main'];
    final weather = json['weather'][0];
    final wind = json['wind'];
    return WeatherData(
      temp: (main['temp'] as num).toDouble(),
      condition: weather['main'],
      description: weather['description'],
      humidity: (main['humidity'] as num).toInt(),
      windSpeed: (wind['speed'] as num).toDouble(),
      visibility: json['visibility'] != null ? (json['visibility'] as num).toInt() : 10000,
    );
  }

  factory WeatherData.mock() {
    return WeatherData(
      temp: 32.5,
      condition: 'Clouds',
      description: 'scattered clouds in Karachi',
      humidity: 74,
      windSpeed: 6.2,
      visibility: 9000,
    );
  }
}

class WeatherAlert {
  final String category;
  final String title;
  final String description;
  final String severity; // High, Warning, Caution

  WeatherAlert({
    required this.category,
    required this.title,
    required this.description,
    required this.severity,
  });
}

class WeatherService {
  final String _apiKey = 'bad4183bd3cb679a7f8d8fd3ab57e34b';

  Future<WeatherData> fetchWeather(double lat, double lon) async {
    final url = Uri.parse(
      'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$_apiKey&units=metric',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return WeatherData.fromJson(data);
      } else {
        return WeatherData.mock();
      }
    } catch (_) {
      return WeatherData.mock();
    }
  }

  // Evaluate weather data for route alerts
  List<WeatherAlert> evaluateWeatherAlerts(WeatherData weather) {
    List<WeatherAlert> alerts = [];

    // 1. Rain / Thunderstorm
    if (weather.condition.toLowerCase().contains('rain') || weather.condition.toLowerCase().contains('drizzle')) {
      alerts.add(WeatherAlert(
        category: 'Heavy Rain',
        title: '🌧️ Heavy Rain & Wet Roads',
        description: 'Slippery road conditions along route. Reduce driving speed.',
        severity: 'Warning',
      ));
    } else if (weather.condition.toLowerCase().contains('thunderstorm')) {
      alerts.add(WeatherAlert(
        category: 'Thunderstorm',
        title: '⚡ Thunderstorm Warning',
        description: 'Severe weather with lightning and high winds ahead.',
        severity: 'High',
      ));
    }

    // 2. High Temperature
    if (weather.temp >= 38.0) {
      alerts.add(WeatherAlert(
        category: 'High Temperature',
        title: '🔥 Extreme Heat Warning (${weather.temp.toStringAsFixed(1)}°C)',
        description: 'High engine & tire heat risk. Monitor tire pressure.',
        severity: 'Caution',
      ));
    }

    // 3. Low Visibility & Fog
    if (weather.visibility < 3000 || weather.condition.toLowerCase().contains('fog') || weather.condition.toLowerCase().contains('mist')) {
      alerts.add(WeatherAlert(
        category: 'Low Visibility',
        title: '🌫️ Fog & Low Visibility (${(weather.visibility / 1000).toStringAsFixed(1)} km)',
        description: 'Poor visibility ahead. Turn on fog lights.',
        severity: 'Warning',
      ));
    }

    // 4. Strong Wind
    if (weather.windSpeed > 12.0) {
      alerts.add(WeatherAlert(
        category: 'Strong Wind',
        title: '💨 Strong Wind Alert (${(weather.windSpeed * 3.6).toStringAsFixed(0)} km/h)',
        description: 'High crosswinds reported on elevated flyovers and open roads.',
        severity: 'Caution',
      ));
    }

    return alerts;
  }
}
