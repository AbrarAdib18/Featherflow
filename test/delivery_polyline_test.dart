import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:featherflow/features/delivery/presentation/screens/delivery_map_screen.dart';

void main() {
  test('decodePolyline decodes the Routes API sample (first/last point)', () {
    final enc = File('test/fixtures/route_polyline.txt').readAsStringSync().trim();
    final pts = decodePolyline(enc);
    expect(pts.length, 126);
    expect(pts.first.latitude, closeTo(23.74989, 1e-5));
    expect(pts.first.longitude, closeTo(90.39039, 1e-5));
    expect(pts.last.latitude, closeTo(23.81037, 1e-5));
  });
}
