import 'package:geolocator/geolocator.dart';

/// A validated delivery location (NF-3).
class DeliveryLocation {
  final double lat;
  final double lng;
  const DeliveryLocation(this.lat, this.lng);

  @override
  String toString() => '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
}

/// Bangladesh bounding box - mirrors backend `delivery/geo.py`.
const _latRange = (20.5, 26.7);
const _lngRange = (88.0, 92.8);

/// Returns null when [lat]/[lng] is a usable Bangladesh location, else a
/// message for the user. Mirrors the server rules so mistakes are caught early.
String? validateDeliveryLocation(double? lat, double? lng) {
  if (lat == null || lng == null) {
    return 'Add your delivery location (use GPS or enter coordinates).';
  }
  if (lat.isNaN || lng.isNaN || lat.isInfinite || lng.isInfinite) {
    return 'Latitude and longitude must be valid numbers.';
  }
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    return 'Latitude must be between -90 and 90 and longitude between -180 and 180.';
  }
  if (lat < _latRange.$1 || lat > _latRange.$2 || lng < _lngRange.$1 || lng > _lngRange.$2) {
    return 'This location is outside the Bangladesh delivery area.';
  }
  return null;
}

/// Parses the two text fields of the manual-entry form.
({double? lat, double? lng, String? error}) parseManualLocation(String latText, String lngText) {
  final lat = double.tryParse(latText.trim());
  final lng = double.tryParse(lngText.trim());
  if (latText.trim().isEmpty && lngText.trim().isEmpty) {
    return (lat: null, lng: null, error: validateDeliveryLocation(null, null));
  }
  if (lat == null || lng == null) {
    return (lat: lat, lng: lng, error: 'Latitude and longitude must be valid numbers.');
  }
  return (lat: lat, lng: lng, error: validateDeliveryLocation(lat, lng));
}

class LocationUnavailable implements Exception {
  final String message;
  const LocationUnavailable(this.message);
  @override
  String toString() => message;
}

/// Fetches the device position. Replaceable in tests.
typedef LocationFetcher = Future<DeliveryLocation> Function();

Future<DeliveryLocation> fetchCurrentLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const LocationUnavailable('Location services are turned off. Enter coordinates manually.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    throw const LocationUnavailable('Location permission was denied. Enter coordinates manually.');
  }
  try {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(const Duration(seconds: 15));
    return DeliveryLocation(p.latitude, p.longitude);
  } catch (_) {
    throw const LocationUnavailable('Could not read your position. Enter coordinates manually.');
  }
}
