import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/delivery_order.dart';
import '../../data/services/delivery_session.dart';
import '../delivery_theme.dart';

List<LatLng> _decodePolyline(String encoded) {
  final points = <LatLng>[];
  int index = 0, lat = 0, lng = 0;
  while (index < encoded.length) {
    int shift = 0, result = 0, b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}

class DeliveryMapScreen extends StatefulWidget {
  final DeliveryOrder? order;

  const DeliveryMapScreen({super.key, this.order});

  @override
  State<DeliveryMapScreen> createState() => _DeliveryMapScreenState();
}

class _DeliveryMapScreenState extends State<DeliveryMapScreen> {
  GoogleMapController? _mapController;
  String? _routeLoadedForOrderId;
  Set<Polyline> _polylines = {};
  double? _routeDistanceKm;
  int? _routeDurationMin;

  Future<void> _loadRoute(DeliveryOrder order) async {
    if (_routeLoadedForOrderId == order.id) return;
    _routeLoadedForOrderId = order.id;
    try {
      final data = await DeliverySession.instance.fetchRoute(order.id);
      final encoded = data['polyline']?.toString();
      if (!mounted || encoded == null) return;
      setState(() {
        _polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            points: _decodePolyline(encoded),
            color: DColors.primary,
            width: 4,
          ),
        };
        _routeDistanceKm = (data['distance_km'] as num?)?.toDouble();
        _routeDurationMin = (data['duration_min'] as num?)?.toInt();
      });
      _fitBounds(order);
    } catch (_) {
      // Route is a nice-to-have; the static pickup/drop markers still render.
    }
  }

  void _fitBounds(DeliveryOrder order) {
    if (_mapController == null ||
        order.pickupLat == null ||
        order.dropLat == null) {
      return;
    }
    final south = order.pickupLat! < order.dropLat! ? order.pickupLat! : order.dropLat!;
    final north = order.pickupLat! > order.dropLat! ? order.pickupLat! : order.dropLat!;
    final west = order.pickupLng! < order.dropLng! ? order.pickupLng! : order.dropLng!;
    final east = order.pickupLng! > order.dropLng! ? order.pickupLng! : order.dropLng!;
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(south, west), northeast: LatLng(north, east)),
      60,
    ));
  }

  Future<void> _navigate(DeliveryOrder order) async {
    final Uri uri;
    if (order.dropLat != null && order.dropLng != null) {
      final origin = order.pickupLat != null && order.pickupLng != null
          ? '${order.pickupLat},${order.pickupLng}'
          : Uri.encodeComponent(order.pickupAddress);
      uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=${order.dropLat},${order.dropLng}');
    } else {
      final origin = Uri.encodeComponent(order.pickupAddress);
      final destination = Uri.encodeComponent(order.dropAddress);
      uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination');
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not open Google Maps.'),
            behavior: SnackBarBehavior.floating));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DeliverySession.instance,
      builder: (context, _) {
        final order = widget.order ?? DeliverySession.instance.activeOrder;
        if (order != null) _loadRoute(order);
        return Scaffold(
          backgroundColor: DColors.bg,
          appBar: AppBar(
            backgroundColor: DColors.appBar,
            elevation: 0,
            title: const Text(
              'Map',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20),
            ),
            actions: [
              if (order != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white38),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.directions_bike, color: Colors.white, size: 13),
                        const SizedBox(width: 4),
                        Text(_statusLabel(order.status),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          body: order == null
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map_outlined, color: DColors.greyDark, size: 48),
                      SizedBox(height: 12),
                      Text('No active delivery to navigate',
                          style: TextStyle(color: DColors.textSecondary, fontSize: 14)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(child: _buildMapArea(order)),
                    _buildBottomPanel(order),
                  ],
                ),
        );
      },
    );
  }

  String _statusLabel(OrderStatus s) => switch (s) {
        OrderStatus.pickedUp => 'Picked Up',
        OrderStatus.onTheWay => 'On The Way',
        _ => 'Accepted',
      };

  Widget _buildMapArea(DeliveryOrder order) {
    final hasCoords = order.pickupLat != null && order.dropLat != null;
    return Stack(
      children: [
        if (hasCoords)
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(order.pickupLat!, order.pickupLng!),
              zoom: 13,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              _fitBounds(order);
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: false,
            polylines: _polylines,
            markers: {
              Marker(
                markerId: const MarkerId('pickup'),
                position: LatLng(order.pickupLat!, order.pickupLng!),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                infoWindow: InfoWindow(title: 'Pickup', snippet: order.pickupAddress),
              ),
              Marker(
                markerId: const MarkerId('drop'),
                position: LatLng(order.dropLat!, order.dropLng!),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                infoWindow: InfoWindow(title: 'Drop-off', snippet: order.dropAddress),
              ),
            },
          )
        else
          Container(
            color: const Color(0xFFE8F0F7),
            alignment: Alignment.center,
            child: const Text('No coordinates available for this order',
                style: TextStyle(color: DColors.textSecondary, fontSize: 13)),
          ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: _buildRouteOverlay(order),
        ),
      ],
    );
  }

  Widget _buildRouteOverlay(DeliveryOrder order) {
    final distance = _routeDistanceKm ?? (order.distanceKm > 0 ? order.distanceKm : null);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: dCard(),
      child: Row(
        children: [
          Column(
            children: [
              const Icon(Icons.radio_button_checked, color: DColors.accent, size: 14),
              Container(width: 1, height: 20, color: DColors.cardBorder),
              const Icon(Icons.location_on, color: DColors.red, size: 14),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.pickupAddress,
                    style: const TextStyle(color: DColors.textSecondary, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Text(order.dropAddress,
                    style: const TextStyle(color: DColors.textSecondary, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(distance != null ? '${distance.toStringAsFixed(1)} km' : '—',
                  style: const TextStyle(
                      color: DColors.accent, fontSize: 13, fontWeight: FontWeight.w700)),
              if (distance != null) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time, color: DColors.grey, size: 11),
                    const SizedBox(width: 3),
                    Text(
                        _routeDurationMin != null
                            ? '~$_routeDurationMin min'
                            : '~${(distance / 20 * 60).round()} min',
                        style: const TextStyle(color: DColors.grey, fontSize: 11)),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(DeliveryOrder order) {
    final distance = _routeDistanceKm ?? (order.distanceKm > 0 ? order.distanceKm : null);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      decoration: const BoxDecoration(
        color: DColors.bg,
        border: Border(top: BorderSide(color: DColors.cardBorder)),
        boxShadow: [
          BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, -2))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _statPill(Icons.straighten, distance != null ? '${distance.toStringAsFixed(1)} km' : '—', DColors.accent),
              const SizedBox(width: 10),
              _statPill(
                  Icons.access_time,
                  _routeDurationMin != null
                      ? '~$_routeDurationMin min'
                      : (distance != null ? '~${(distance / 20 * 60).round()} min' : '—'),
                  DColors.textSecondary),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _navigate(order),
              icon: const Icon(Icons.navigation, size: 18),
              label: const Text('Open in Google Maps',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: DColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statPill(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: dCard(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
