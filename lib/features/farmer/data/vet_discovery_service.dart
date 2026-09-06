import 'farm_management_service.dart';

class VetDiscoveryService {
  static Future<Map<String, dynamic>> discover({
    String search = '',
    String? mode,
    String? specialty,
    bool available = false,
    bool emergency = false,
    bool verified = false,
    double? latitude,
    double? longitude,
    double? maxFee,
    double? minRating,
  }) {
    final query = <String, String>{
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (mode != null) 'mode': mode,
      if (specialty != null) 'specialty': specialty,
      if (available) 'available': 'true',
      if (emergency) 'emergency': 'true',
      if (verified) 'verified': 'true',
      if (latitude != null) 'latitude': '$latitude',
      if (longitude != null) 'longitude': '$longitude',
      if (maxFee != null) 'max_fee': '$maxFee',
      if (minRating != null) 'min_rating': '$minRating',
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    return FarmManagementService.get('consultations/vets$suffix');
  }

  static Future<Map<String, dynamic>> detail(String profileId) =>
      FarmManagementService.get('consultations/vets/$profileId');

  static Future<Map<String, dynamic>> bookingOptions(String profileId,
      {DateTime? date, String? mode}) {
    final query = <String, String>{
      if (date != null) 'date': formatDate(date),
      if (mode != null) 'mode': mode,
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    return FarmManagementService.get(
        'consultations/vets/$profileId/booking-options$suffix');
  }

  static Future<Map<String, dynamic>> book(Map<String, dynamic> body) =>
      FarmManagementService.post('consultations', body);

  static String formatDate(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
