class IncidentModel {
  final String id;
  final String reporterName;
  final String reporterPhone;
  final String category;
  final double lat;
  final double lng;
  final String status;
  final DateTime timestamp;
  final String? notes;
  final String? assignedUnit;
  final String? assignedVehicle;

  const IncidentModel({
    required this.id,
    required this.reporterName,
    required this.reporterPhone,
    required this.category,
    required this.lat,
    required this.lng,
    required this.status,
    required this.timestamp,
    this.notes,
    this.assignedUnit,
    this.assignedVehicle,
  });

  factory IncidentModel.fromJson(Map<String, dynamic> json) {
    return IncidentModel(
      id: json['id']?.toString() ?? '',
      reporterName: json['reporter_name'] as String? ?? 'Unknown',
      reporterPhone: json['reporter_phone'] as String? ?? '',
      category: json['category'] as String? ?? 'SOS',
      lat: (json['lat'] as num?)?.toDouble() ?? 16.1086,
      lng: (json['lng'] as num?)?.toDouble() ?? 120.5424,
      status: json['status'] as String? ?? 'active',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
      notes: json['notes'] as String?,
      assignedUnit: json['assignedUnit'] as String?,
      assignedVehicle: json['assignedVehicle'] as String?,
    );
  }
}
