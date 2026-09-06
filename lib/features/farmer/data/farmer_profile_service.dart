import 'farm_management_service.dart';

/// /api/farmers/profile/ + /api/farmers/dashboard/ + shed/flock (batch) CRUD.
class FarmerProfileService {
  static Future<Map<String, dynamic>> get() =>
      FarmManagementService.get('farmers/profile');

  static Future<Map<String, dynamic>> update(Map<String, dynamic> body) =>
      FarmManagementService.patch('farmers/profile', body);

  static Future<Map<String, dynamic>> uploadPhoto(
      List<int> bytes, String filename) async {
    return FarmManagementService.upload(
        'farmers/profile/upload-photo', bytes, filename);
  }

  static Future<Map<String, dynamic>> deletePhoto(String url) =>
      FarmManagementService.delete(
          'farmers/profile/upload-photo', {'image_url': url});

  // ── home dashboard aggregate ─────────────────────────────────────────
  static Future<Map<String, dynamic>> homeDashboard() =>
      FarmManagementService.get('farmers/dashboard');

  // ── sheds ────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> sheds() =>
      FarmManagementService.get('farmers/sheds');

  static Future<Map<String, dynamic>> addShed(Map<String, dynamic> body) =>
      FarmManagementService.post('farmers/sheds', body);

  // ── flocks (batches) ────────────────────────────────────────────────
  static Future<Map<String, dynamic>> flocks({String? status}) =>
      FarmManagementService.get(
          'farmers/flocks${status == null ? '' : '?status=$status'}');

  static Future<Map<String, dynamic>> addFlock(Map<String, dynamic> body) =>
      FarmManagementService.post('farmers/flocks', body);

  static Future<Map<String, dynamic>> updateFlock(
          String id, Map<String, dynamic> body) =>
      FarmManagementService.patch('farmers/flocks/$id', body);
}
