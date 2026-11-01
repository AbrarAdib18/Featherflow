import '../services/delivery_api_service.dart';

/// Why a route could not be shown. Mirrors the backend `code` values of
/// `GET /api/delivery/orders/<id>/route/` (delivery/routing.py).
enum RouteFailure {
  locationMissing,
  noRoute,
  configuration,
  quota,
  unreachable,
  timeout,
  unknown,
}

class RouteInfo {
  final String polyline;
  final double distanceKm;
  final int durationMin;
  final String provider;

  const RouteInfo({
    required this.polyline,
    required this.distanceKm,
    required this.durationMin,
    this.provider = '',
  });

  factory RouteInfo.fromJson(Map<String, dynamic> j) => RouteInfo(
        polyline: j['polyline']?.toString() ?? '',
        distanceKm: (j['distance_km'] as num?)?.toDouble() ?? 0,
        durationMin: (j['duration_min'] as num?)?.toInt() ?? 0,
        provider: j['provider']?.toString() ?? '',
      );
}

class RouteLoadException implements Exception {
  final RouteFailure failure;
  final String message;
  const RouteLoadException(this.failure, this.message);

  /// Failures a rider cannot fix by retrying.
  bool get isConfiguration =>
      failure == RouteFailure.configuration;

  @override
  String toString() => message;
}

RouteFailure routeFailureFromCode(String? code, int? status) => switch (code) {
      'location_missing' => RouteFailure.locationMissing,
      'no_route' => RouteFailure.noRoute,
      'routing_not_configured' || 'routing_configuration_error' => RouteFailure.configuration,
      'routing_quota_exceeded' => RouteFailure.quota,
      'routing_timeout' => RouteFailure.timeout,
      'routing_unreachable' => RouteFailure.unreachable,
      _ => RouteFailure.unknown,
    };

/// Loads route + ETA for one order, translating API errors into
/// [RouteLoadException]s the UI can present.
Future<RouteInfo> loadRouteInfo(String orderId) async {
  try {
    final data = await DeliveryApiService.route(orderId);
    final info = RouteInfo.fromJson(data);
    if (info.polyline.isEmpty) {
      throw const RouteLoadException(
          RouteFailure.noRoute, 'No route could be found between these locations.');
    }
    return info;
  } on RouteLoadException {
    rethrow;
  } on DeliveryApiException catch (e) {
    throw RouteLoadException(routeFailureFromCode(e.code, e.statusCode), e.message);
  } catch (e) {
    throw RouteLoadException(RouteFailure.unreachable, 'Could not reach the server: $e');
  }
}
