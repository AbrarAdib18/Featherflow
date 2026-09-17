import 'farm_management_service.dart';

/// Wraps the flock CRUD + flock-event + age-based feed-chart endpoints
/// (Priority 4 — see FEED_AND_DATA_INTEGRITY_AUDIT.md). Reuses
/// [FarmManagementService] for auth/error handling like every other farmer
/// data service. All paths are under `/api/farmers/...` — `FarmManagementService`
/// does not add that prefix itself (confirmed against `farmer_profile_service.dart`,
/// which already has its own, separate `flocks()`/`addFlock()` pair for the
/// Sheds & Batches screen; this service additionally covers flock events and
/// the age-based feed chart that screen doesn't need).
class FlockService {
  static Future<List<Map<String, dynamic>>> list({String? status}) async {
    final res = await FarmManagementService.get(
        status != null ? 'farmers/flocks?status=$status' : 'farmers/flocks');
    return ((res['results'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<Map<String, dynamic>> create(Map<String, dynamic> body) =>
      FarmManagementService.post('farmers/flocks', body);

  static Future<Map<String, dynamic>> update(String id, Map<String, dynamic> body) =>
      FarmManagementService.patch('farmers/flocks/$id', body);

  static Future<Map<String, dynamic>> feedChart(String flockId) =>
      FarmManagementService.get('farmers/flocks/$flockId/feed-chart');

  static Future<List<Map<String, dynamic>>> events(String flockId) async {
    final res = await FarmManagementService.get('farmers/flocks/$flockId/events');
    return ((res['results'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<Map<String, dynamic>> logEvent(String flockId, Map<String, dynamic> body) =>
      FarmManagementService.post('farmers/flocks/$flockId/events', body);
}
