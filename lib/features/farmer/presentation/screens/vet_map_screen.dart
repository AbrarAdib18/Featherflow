import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:featherflow/core/theme/theme.dart';
import '../../data/vet_discovery_service.dart';
import '../widgets/vet_map.dart';

/// Simple "find nearby vets" tool: the farmer's real GPS location plus vets
/// within ~50 km, each with an "Open in Google Maps" link. No in-app routing,
/// no filters.
class VetMapScreen extends StatefulWidget {
  const VetMapScreen({super.key});

  @override
  State<VetMapScreen> createState() => _VetMapScreenState();
}

enum _LocState { checking, denied, failed, ready }

class _VetMapScreenState extends State<VetMapScreen> {
  static const double _radiusKm = 50;
  static const LatLng _fallbackCenter = LatLng(23.8103, 90.4125); // Dhaka

  final MapController _mapController = MapController();
  final Distance _distance = const Distance();

  _LocState _locState = _LocState.checking;
  LatLng? _userLatLng;

  bool _loadingVets = false;
  String? _vetsError;
  List<Map<String, dynamic>> _vets = const [];
  String? _selectedVetId;

  String? _fromDisease; // set when opened from Disease Detection
  bool _readQuery = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_readQuery) return;
    _readQuery = true;
    _fromDisease = GoRouterState.of(context).uri.queryParameters['disease'];
  }

  // ── location ──────────────────────────────────────────────────────────────
  Future<void> _init() async {
    setState(() => _locState = _LocState.checking);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _locState = _LocState.failed);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _locState = _LocState.denied);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        _userLatLng = LatLng(pos.latitude, pos.longitude);
        _locState = _LocState.ready;
      });
      try {
        _mapController.move(_userLatLng!, 13);
      } catch (_) {}
      await _loadVets();
    } catch (_) {
      if (mounted) setState(() => _locState = _LocState.failed);
    }
  }

  Future<void> _openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  // ── vets ──────────────────────────────────────────────────────────────────
  Future<void> _loadVets() async {
    final me = _userLatLng;
    if (me == null) return;
    setState(() {
      _loadingVets = true;
      _vetsError = null;
    });
    try {
      final vets = await VetDiscoveryService.nearby(
        latitude: me.latitude,
        longitude: me.longitude,
        radiusKm: _radiusKm,
      );
      if (!mounted) return;
      setState(() {
        _vets = vets;
        _loadingVets = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitToContent());
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingVets = false;
          _vetsError = 'Failed to load vets. Please try again.';
        });
      }
    }
  }

  void _fitToContent() {
    final me = _userLatLng;
    if (me == null) return;
    final pts = <LatLng>[me, ..._vetPoints.map((v) => v.location)];
    if (pts.length < 2) {
      try {
        _mapController.move(me, 13);
      } catch (_) {}
      return;
    }
    try {
      _mapController.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.all(48),
        maxZoom: 14,
      ));
    } catch (_) {}
  }

  void _recenter() {
    final me = _userLatLng;
    if (me == null) {
      _init();
      return;
    }
    try {
      _mapController.move(me, 14);
    } catch (_) {}
  }

  List<VetPoint> get _vetPoints => _vets
      .where((v) => v['latitude'] != null && v['longitude'] != null)
      .map((v) => VetPoint(
            id: v['id'].toString(),
            location: LatLng((v['latitude'] as num).toDouble(),
                (v['longitude'] as num).toDouble()),
            name: v['name']?.toString() ?? 'Vet',
            clinic: v['clinic_name']?.toString() ?? '',
          ))
      .toList();

  double? _distanceKm(Map<String, dynamic> vet) {
    final me = _userLatLng;
    if (me != null && vet['latitude'] != null && vet['longitude'] != null) {
      return _distance.as(
        LengthUnit.Kilometer,
        me,
        LatLng((vet['latitude'] as num).toDouble(),
            (vet['longitude'] as num).toDouble()),
      );
    }
    final api = vet['distance_km'];
    return api == null ? null : (api as num).toDouble();
  }

  // ── actions ───────────────────────────────────────────────────────────────
  Future<void> _openInGoogleMaps(Map<String, dynamic> vet) async {
    final lat = (vet['latitude'] as num?)?.toDouble();
    final lng = (vet['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      _snack('This vet has not saved a map location yet.');
      return;
    }
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication)
        .catchError((_) => false);
    if (!ok) {
      await launchUrl(uri).catchError((_) => false);
    }
  }

  Future<void> _call(Map<String, dynamic> vet) async {
    final phone = (vet['phone'] ?? '').toString().trim();
    if (phone.isEmpty) {
      _snack('No phone number on file for this vet.');
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    final ok = await launchUrl(uri).catchError((_) => false);
    if (!ok) _snack('Call this vet at $phone');
  }

  void _snack(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void _onVetTap(VetPoint point) {
    final vet = _vets.firstWhere((v) => v['id'].toString() == point.id,
        orElse: () => const {});
    if (vet.isEmpty) return;
    setState(() => _selectedVetId = point.id);
    _showVetCard(vet);
  }

  void _showVetCard(Map<String, dynamic> vet) {
    final km = _distanceKm(vet);
    final rating = (vet['rating'] as num?)?.toDouble();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Icon(Icons.local_hospital, color: Colors.red, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vet['name']?.toString() ?? 'Vet',
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary)),
                    if ((vet['clinic_name']?.toString() ?? '').isNotEmpty)
                      Text(vet['clinic_name'].toString(),
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.hint)),
                  ]),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.near_me_outlined, size: 15, color: AppColors.hint),
            const SizedBox(width: 4),
            Text(
              km == null ? 'Distance unavailable' : '${km.toStringAsFixed(1)} km away',
              style: const TextStyle(fontSize: 13, color: AppColors.hint),
            ),
            const Spacer(),
            if (rating != null && rating > 0) ...[
              const Icon(Icons.star, size: 15, color: Colors.amber),
              const SizedBox(width: 3),
              Text(rating.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ]),
          if ((vet['address']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.location_on_outlined,
                  size: 15, color: AppColors.hint),
              const SizedBox(width: 4),
              Expanded(
                child: Text(vet['address'].toString(),
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.hint)),
              ),
            ]),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _call(vet);
                },
                icon: const Icon(Icons.call, size: 16),
                label: const Text('Call'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openInGoogleMaps(vet);
                },
                icon: const Icon(Icons.map_outlined, size: 16),
                label: const Text('Open in Google Maps'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/farmer'),
        ),
        title: const Text('Find a Vet Near You',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
              icon: const Icon(Icons.home, color: Colors.white),
              onPressed: () => context.go('/farmer')),
        ],
      ),
      body: switch (_locState) {
        _LocState.checking => const Center(child: CircularProgressIndicator()),
        _LocState.denied => _LocationMessage(
            icon: Icons.location_off_outlined,
            message: 'Location access is required to find vets near you',
            primaryLabel: 'Open app settings',
            onPrimary: _openAppSettings,
            onRetry: _init,
          ),
        _LocState.failed => _LocationMessage(
            icon: Icons.gps_off_outlined,
            message: 'Unable to get your location. Please enable GPS and try again.',
            primaryLabel: 'Try again',
            onPrimary: _init,
          ),
        _LocState.ready => _content(),
      },
    );
  }

  Widget _content() {
    return RefreshIndicator(
      onRefresh: _loadVets,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (_fromDisease != null) ...[
            _Banner(text:
                'From disease detection: "$_fromDisease". Mention this when you contact the vet.'),
            const SizedBox(height: AppSpacing.sm),
          ],
          ClipRRect(
            borderRadius: AppRadius.lgAll,
            child: SizedBox(
              height: 320,
              child: VetMap(
                controller: _mapController,
                center: _userLatLng ?? _fallbackCenter,
                userLocation: _userLatLng,
                vets: _vetPoints,
                selectedVetId: _selectedVetId,
                onVetTap: _onVetTap,
                onRecenter: _recenter,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.place_outlined, size: 13, color: AppColors.hint),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _loadingVets
                    ? 'Finding vets near you…'
                    : '${_vets.length} vet(s) within ${_radiusKm.toStringAsFixed(0)} km • blue marker is you',
                style: const TextStyle(fontSize: 11, color: AppColors.hint),
              ),
            ),
            TextButton.icon(
              onPressed: _loadingVets ? null : _loadVets,
              icon: const Icon(Icons.refresh, size: 15),
              label: const Text('Refresh'),
            ),
          ]),
          const SizedBox(height: 8),
          const Text('Nearby vets',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary)),
          const SizedBox(height: 8),
          if (_loadingVets && _vets.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_vetsError != null)
            _ErrorCard(message: _vetsError!, onRetry: _loadVets)
          else if (_vets.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No vets found near you. Try increasing the search radius or check back later.',
                style: TextStyle(color: AppColors.hint),
              ),
            )
          else
            ..._vets.map(_vetListCard),
        ],
      ),
    );
  }

  Widget _vetListCard(Map<String, dynamic> vet) {
    final km = _distanceKm(vet);
    final rating = (vet['rating'] as num?)?.toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.secondary.withValues(alpha: .18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(vet['name']?.toString() ?? 'Vet',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary)),
                  if ((vet['clinic_name']?.toString() ?? '').isNotEmpty)
                    Text(vet['clinic_name'].toString(),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.hint)),
                ]),
          ),
          if (rating != null && rating > 0) ...[
            const Icon(Icons.star, size: 14, color: Colors.amber),
            const SizedBox(width: 2),
            Text(rating.toStringAsFixed(1),
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
          ],
          Text(km == null ? '—' : '${km.toStringAsFixed(1)} km',
              style: const TextStyle(fontSize: 12, color: AppColors.hint)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _call(vet),
              icon: const Icon(Icons.call, size: 15),
              label: const Text('Call'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _openInGoogleMaps(vet),
              icon: const Icon(Icons.map_outlined, size: 15),
              label: const Text('Open in Google Maps'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _LocationMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback? onRetry;

  const _LocationMessage({
    required this.icon,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: AppColors.hint),
          const SizedBox(height: 16),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Colors.black87)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: onPrimary,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            child: Text(primaryLabel),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Try again')),
        ]),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, color: AppColors.error, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  const _Banner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.07),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.coronavirus_outlined,
            size: 18, color: AppColors.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(fontSize: 12, color: Colors.black87)),
        ),
      ]),
    );
  }
}
