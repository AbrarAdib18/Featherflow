import 'package:flutter/material.dart';
import '../../data/models/delivery_order.dart';
import '../../data/models/route_info.dart';
import '../delivery_theme.dart';

typedef RouteLoader = Future<RouteInfo> Function(String orderId);

/// Route + ETA panel for one delivery (F-003). Handles every state the rider
/// can see: loading, route available (distance + ETA), route unavailable,
/// server configuration error, location missing — each with Retry (when a
/// retry can help) and a manual "navigate by address" fallback, plus a clearly
/// labelled straight-line estimate so the rider is never left without numbers.
class RouteSummaryCard extends StatefulWidget {
  final DeliveryOrder order;
  final RouteLoader loader;
  final ValueChanged<RouteInfo>? onRoute;
  final VoidCallback onOpenMaps;

  const RouteSummaryCard({
    super.key,
    required this.order,
    required this.loader,
    required this.onOpenMaps,
    this.onRoute,
  });

  @override
  State<RouteSummaryCard> createState() => _RouteSummaryCardState();
}

class _RouteSummaryCardState extends State<RouteSummaryCard> {
  RouteInfo? _route;
  RouteLoadException? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RouteSummaryCard old) {
    super.didUpdateWidget(old);
    if (old.order.id != widget.order.id) {
      _route = null;
      _load();
    }
  }

  bool get _hasLocation =>
      (widget.order.pickupLat != null && widget.order.dropLat != null) ||
      (widget.order.pickupAddress.trim().isNotEmpty &&
          widget.order.dropAddress.trim().isNotEmpty);

  Future<void> _load() async {
    if (!_hasLocation) {
      setState(() {
        _route = null;
        _error = const RouteLoadException(
            RouteFailure.locationMissing, 'This order has no pickup/drop location.');
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final orderId = widget.order.id;
    try {
      final info = await widget.loader(orderId);
      if (!mounted || orderId != widget.order.id) return;
      setState(() {
        _route = info;
        _loading = false;
      });
      widget.onRoute?.call(info);
    } on RouteLoadException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = RouteLoadException(RouteFailure.unknown, e.toString());
        _loading = false;
      });
    }
  }

  String _errorTitle(RouteFailure f) => switch (f) {
        RouteFailure.locationMissing => 'Location missing',
        RouteFailure.configuration => 'Route service configuration error',
        RouteFailure.noRoute => 'No route found',
        RouteFailure.quota => 'Route service busy',
        RouteFailure.timeout => 'Route service timed out',
        _ => 'Route unavailable',
      };

  String _errorHelp(RouteFailure f) => switch (f) {
        RouteFailure.locationMissing =>
          'No coordinates for this order. Navigate using the addresses below.',
        RouteFailure.configuration =>
          'Routing is not set up correctly on the server - please tell an admin. Navigate using the addresses below meanwhile.',
        RouteFailure.noRoute => 'No drivable route between these points. Check the addresses.',
        _ => 'Live route and ETA could not be loaded. Retry, or navigate by address.',
      };

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final route = _route;
    final err = _error;
    final estimateKm = order.distanceKm > 0 ? order.distanceKm : null;
    final distance = route?.distanceKm ?? estimateKm;
    final etaMin =
        route?.durationMin ?? (distance != null ? (distance / 20 * 60).round() : null);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      decoration: const BoxDecoration(
        color: DColors.bg,
        border: Border(top: BorderSide(color: DColors.cardBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: DColors.accent)),
                SizedBox(width: 10),
                Text('Finding route...',
                    key: Key('routeLoading'),
                    style: TextStyle(color: DColors.textSecondary, fontSize: 12)),
              ]),
            ),
          if (err != null) ...[
            Container(
              key: const Key('routeError'),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: err.isConfiguration ? DColors.redLight : DColors.orangeLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_errorTitle(err.failure),
                      key: Key('routeErrorTitle_${err.failure.name}'),
                      style: TextStyle(
                          color: err.isConfiguration ? DColors.red : DColors.orange,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(_errorHelp(err.failure),
                      style: const TextStyle(color: DColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              _pill(Icons.straighten, distance != null ? '${distance.toStringAsFixed(1)} km' : '-',
                  DColors.accent, const Key('routeDistance')),
              const SizedBox(width: 10),
              _pill(
                  Icons.access_time,
                  etaMin != null
                      ? (route != null ? 'ETA ~$etaMin min' : 'Est. ~$etaMin min')
                      : '-',
                  DColors.textSecondary,
                  const Key('routeEta')),
              const Spacer(),
              if (err != null && err.failure != RouteFailure.locationMissing)
                TextButton.icon(
                  key: const Key('routeRetry'),
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const Key('routeOpenMaps'),
              onPressed: widget.onOpenMaps,
              icon: const Icon(Icons.navigation, size: 18),
              label: Text(err != null ? 'Navigate by address' : 'Open in Google Maps',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: DColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          if (err != null) ...[
            const SizedBox(height: 10),
            Text('Pickup: ${order.pickupAddress}',
                key: const Key('routeFallbackPickup'),
                style: const TextStyle(color: DColors.textSecondary, fontSize: 12)),
            Text('Drop: ${order.dropAddress}',
                key: const Key('routeFallbackDrop'),
                style: const TextStyle(color: DColors.textSecondary, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String label, Color color, Key key) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: dCard(),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(label,
              key: key,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}
