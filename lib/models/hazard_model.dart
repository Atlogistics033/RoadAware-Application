class HazardModel {
  final String id;
  final String type; // 'Traffic Jam', 'Road Condition', 'Accident', 'Rain', 'Pothole'
  final double latitude;
  final double longitude;
  final String message;
  final String? imagePath; // Path to mock selected image
  final DateTime timestamp;
  final String reportedBy; // Name of user or 'Admin'
  final bool isApproved; // Whether it is active

  HazardModel({
    required this.id,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.message,
    this.imagePath,
    required this.timestamp,
    required this.reportedBy,
    this.isApproved = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'latitude': latitude,
        'longitude': longitude,
        'message': message,
        'imagePath': imagePath,
        'timestamp': timestamp.toIso8601String(),
        'reportedBy': reportedBy,
        'isApproved': isApproved,
      };

  factory HazardModel.fromJson(Map<String, dynamic> json) => HazardModel(
        id: json['id'],
        type: json['type'],
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        message: json['message'],
        imagePath: json['imagePath'],
        timestamp: DateTime.parse(json['timestamp']),
        reportedBy: json['reportedBy'],
        isApproved: json['isApproved'] ?? true,
      );
}
