import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/delivery_order.dart';
import '../../data/models/route_info.dart';
import '../widgets/route_summary_card.dart';
import '../../data/services/delivery_session.dart';
import '../delivery_theme.dart';

@visibleForTesting
/// Decodes a Google encoded polyline. Note: `-(x) - 1` rather than `~x` - on the
/// web (dart2js) `~x` yields an UNSIGNED 32-bit value, which silently corrupted
/// every route that went south/west of the previous point.
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  int index = 0, lat = 0, lng = 0;
  while (index < encoded.length) {
    int shift = 0, result = 0, b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lat += (result & 1) != 0 ? -(result >> 1) - 1 : (result >> 1);

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lng += (result & 1) != 0 ? -(result >> 1) - 1 : (result >> 1);

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
  Set<Polyline> _polylines = {};
  List<LatLng> _routePoints = const [];
  /// Which delivery the polyline above belongs to - a route is never shown for a
  /// different order (NF-4).
  String? _routeOrderId;

  void _onRoute(RouteInfo info, DeliveryOrder order) {
    if (!mounted) return;
    final points = decodePolyline(info.polyline);
    setState(() {
      _routeOrderId = order.id;
      _routePoints = points;
      _polylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          points: points,
          color: DColors.primary,
          width: 4,
        ),
      };
    });
    _fitBounds(order);
  }

  void _fitBounds(DeliveryOrder order) {
    final pts = <LatLng>[
      ..._routePoints,
      if (order.pickupLat != null && order.pickupLng != null) LatLng(order.pickupLat!, order.pickupLng!),
      if (order.dropLat != null && order.dropLng != null) LatLng(order.dropLat!, order.dropLng!),
    ];
    if (_mapController == null || pts.length < 2) return;
    var south = pts.first.latitude, north = south;
    var west = pts.first.longitude, east = west;
    for (final p in pts) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    // newLatLngBounds depends on the map view already having a size, which is
    // not guaranteed on web right after creation (it zoomed to the whole world).
    // Centre + an explicit zoom derived from the span is deterministic.
    final span = [north - south, (east - west) * 0.92, 0.004].reduce((a, b) => a > b ? a : b);
    final zoom = (math.log(360 / span) / math.ln2 - 1.2).clamp(3.0, 17.0);
    _mapController!.animateCamera(CameraUpdate.newLatLngZoom(
      LatLng((south + north) / 2, (west + east) / 2),
      zoom,
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
        final session = DeliverySession.instance;
        // NF-4: bind to the selected delivery, never silently to "the first
        // active order". With exactly one active delivery it is unambiguous;
        // with several the rider must choose.
        final active = session.activeOrders;
        DeliveryOrder? order = widget.order ?? session.selectedOrder;
        // A selection that is no longer an active delivery (delivered, rejected,
        // reassigned) is dropped after a refresh instead of lingering.
        if (widget.order == null && order != null && !active.any((o) => o.id == order!.id)) {
          order = null;
        }
        if (order == null && active.length == 1) order = active.first;
        final needsChoice = order == null && active.length > 1;
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
              if (widget.order == null && order != null && session.activeOrders.length > 1)
                IconButton(
                  key: const Key('mapChangeDelivery'),
                  tooltip: 'Change delivery',
                  icon: const Icon(Icons.swap_horiz, color: Colors.white),
                  onPressed: () => DeliverySession.instance.selectOrder(null),
                ),
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
          body: needsChoice
              ? _buildChooser(active)
              : order == null
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

  Widget _buildChooser(List<DeliveryOrder> active) {
    return ListView(
      key: const Key('mapChooser'),
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Which delivery do you want to navigate?',
            style: TextStyle(color: DColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('You have several active deliveries - pick one to see its route and ETA.',
            style: TextStyle(color: DColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 12),
        for (final o in active)
          Card(
            child: ListTile(
              key: Key('mapChoose_${o.id}'),
              leading: const Icon(Icons.local_shipping_outlined, color: DColors.primary),
              title: Text('#${o.id.length > 8 ? o.id.substring(0, 8).toUpperCase() : o.id}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.pickupAddress, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('-> ${o.dropAddress}',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              trailing: Text(_statusLabel(o.status),
                  style: const TextStyle(color: DColors.accent, fontWeight: FontWeight.w600, fontSize: 12)),
              isThreeLine: true,
              onTap: () => DeliverySession.instance.selectOrder(o.id),
            ),
          ),
      ],
    );
  }

  String _statusLabel(OrderStatus s) => switch (s) {
        OrderStatus.pickedUp => 'Picked Up',
        OrderStatus.onTheWay => 'Out for delivery',
        OrderStatus.arrived => 'Arrived',
        OrderStatus.proofSubmitted => 'Proof under review',
        OrderStatus.proofRejected => 'Proof rejected',
        _ => 'Accepted',
      };

  Widget _buildMapArea(DeliveryOrder order) {
    final hasCoords = order.dropLat != null && order.dropLng != null;
    final hasPickup = order.pickupLat != null && order.pickupLng != null;
    return Stack(
      children: [
        if (hasCoords)
          GoogleMap(
            key: ValueKey('map_${order.id}'),
            initialCameraPosition: CameraPosition(
              target: hasPickup
                  ? LatLng(order.pickupLat!, order.pickupLng!)
                  : LatLng(order.dropLat!, order.dropLng!),
              zoom: 13,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              _fitBounds(order);
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: false,
            polylines: _routeOrderId == order.id ? _polylines : const <Polyline>{},
            markers: {
              if (hasPickup)
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
            padding: const EdgeInsets.all(24),
            child: const Text('No map coordinates for this order - use the addresses below',
                key: Key('mapNoCoordinates'),
                textAlign: TextAlign.center,
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
    final distance = order.distanceKm > 0 ? order.distanceKm : null;
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
                    Text('~${(distance / 20 * 60).round()} min',
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
    return RouteSummaryCard(
      key: ValueKey('route_${order.id}'),
      order: order,
      loader: loadRouteInfo,
      onRoute: (info) => _onRoute(info, order),
      onOpenMaps: () => _navigate(order),
    );
  }
}
