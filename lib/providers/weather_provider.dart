import 'package:flutter/material.dart';
import '../services/weather_service.dart';

class WeatherProvider extends ChangeNotifier {
  final WeatherService _weatherService = WeatherService();
  WeatherData? _weatherData;
  bool _isLoading = false;
  String? _errorMessage;

  WeatherData? get weatherData => _weatherData;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Retrieve current weather conditions
  Future<void> loadWeather(double lat, double lon) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _weatherData = await _weatherService.fetchWeather(lat, lon);
    } catch (e) {
      _weatherData = WeatherData.mock();
      _errorMessage = 'Failed to load weather: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
