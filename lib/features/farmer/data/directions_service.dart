import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Keyless driving directions via the public OSRM demo server
/// (https://router.project-osrm.org). Returns the road-following route
/// geometry plus distance / duration, or a straight line fallback.
class DirectionsResult {
  final List<LatLng> points;
  final double distanceKm;
  final int durationMin;
  final bool approximate;

  const DirectionsResult({
    required this.points,
    required this.distanceKm,
    required this.durationMin,
    this.approximate = false,
  });
}

class DirectionsService {
  static Future<DirectionsResult> route(LatLng from, LatLng to) async {
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
      '?overview=full&geometries=geojson',
    );
    try {
      final r = await http.get(uri).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final routes = body['routes'] as List? ?? const [];
        if (routes.isNotEmpty) {
          final route = routes.first as Map<String, dynamic>;
          final coords = (route['geometry']?['coordinates'] as List? ?? const [])
              .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
              .toList();
          if (coords.isNotEmpty) {
            return DirectionsResult(
              points: coords,
              distanceKm: ((route['distance'] as num?) ?? 0) / 1000,
              durationMin: (((route['duration'] as num?) ?? 0) / 60).round(),
            );
          }
        }
      }
    } catch (_) {
      // fall through to the straight-line estimate
    }
    const distance = Distance();
    final km = distance.as(LengthUnit.Kilometer, from, to);
    return DirectionsResult(
      points: [from, to],
      distanceKm: km,
      durationMin: (km / 30 * 60).round(), // ~30 km/h town driving
      approximate: true,
    );
  }
}
