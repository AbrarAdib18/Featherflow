import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:featherflow/core/theme/theme.dart';

/// One vet plotted on the map.
class VetPoint {
  final String id;
  final LatLng location;
  final String name;
  final String specialty;
  final bool available;

  const VetPoint({
    required this.id,
    required this.location,
    required this.name,
    this.specialty = '',
    this.available = true,
  });
}

/// In-app interactive map (OpenStreetMap tiles — no API key, works on every
/// platform incl. Windows desktop). Shows the farmer's live location, nearby
/// vet pins, and an optional driving route.
class VetMap extends StatelessWidget {
  final MapController controller;
  final LatLng center;
  final LatLng? userLocation;
  final List<VetPoint> vets;
  final String? selectedVetId;
  final List<LatLng> route;
  final void Function(VetPoint vet) onVetTap;
  final VoidCallback? onRecenter;

  const VetMap({
    super.key,
    required this.controller,
    required this.center,
    required this.vets,
    required this.onVetTap,
    this.userLocation,
    this.selectedVetId,
    this.route = const [],
    this.onRecenter,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      FlutterMap(
        mapController: controller,
        options: MapOptions(
          initialCenter: center,
          initialZoom: 12,
          minZoom: 4,
          maxZoom: 18,
          // No scroll-wheel zoom: the map sits inside a scrolling page, so the
          // wheel must scroll the page. Desktop users zoom with the +/- buttons
          // or double-tap; touch users pinch.
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.pinchZoom |
                InteractiveFlag.drag |
                InteractiveFlag.doubleTapZoom |
                InteractiveFlag.flingAnimation,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.featherflow.app',
            maxNativeZoom: 19,
          ),
          if (route.length > 1)
            PolylineLayer(polylines: [
              Polyline(
                points: route,
                strokeWidth: 4,
                color: AppColors.primary,
              ),
            ]),
          MarkerLayer(markers: [
            if (userLocation != null)
              Marker(
                point: userLocation!,
                width: 26,
                height: 26,
                child: const _UserDot(),
              ),
            for (final vet in vets)
              Marker(
                point: vet.location,
                width: 40,
                height: 40,
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  onTap: () => onVetTap(vet),
                  child: _VetPin(
                    selected: vet.id == selectedVetId,
                    available: vet.available,
                  ),
                ),
              ),
          ]),
          const _OsmAttribution(),
        ],
      ),
      Positioned(
        right: 10,
        top: 10,
        child: Column(children: [
          _MapButton(
            icon: Icons.add,
            onTap: () => _nudgeZoom(1),
          ),
          const SizedBox(height: 6),
          _MapButton(
            icon: Icons.remove,
            onTap: () => _nudgeZoom(-1),
          ),
        ]),
      ),
      if (onRecenter != null)
        Positioned(
          right: 10,
          bottom: 26,
          child: FloatingActionButton.small(
            heroTag: 'vetmap-recenter',
            backgroundColor: Colors.white,
            foregroundColor: AppColors.primary,
            onPressed: onRecenter,
            child: const Icon(Icons.my_location),
          ),
        ),
    ]);
  }

  void _nudgeZoom(double delta) {
    try {
      final camera = controller.camera;
      controller.move(camera.center, (camera.zoom + delta).clamp(4, 18));
    } catch (_) {}
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MapButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
      ),
    );
  }
}

class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.25),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
          ),
        ),
      ),
    );
  }
}

class _VetPin extends StatelessWidget {
  final bool selected;
  final bool available;

  const _VetPin({required this.selected, required this.available});

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? AppColors.primary
        : (available ? AppColors.secondary : Colors.grey);
    return Icon(
      Icons.location_on,
      color: color,
      size: selected ? 40 : 32,
      shadows: const [Shadow(color: Colors.black38, blurRadius: 3)],
    );
  }
}

class _OsmAttribution extends StatelessWidget {
  const _OsmAttribution();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: EdgeInsets.all(2),
        child: DecoratedBox(
          decoration: BoxDecoration(color: Color(0xCCFFFFFF)),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            child: Text('© OpenStreetMap',
                style: TextStyle(fontSize: 9, color: Colors.black54)),
          ),
        ),
      ),
    );
  }
}
