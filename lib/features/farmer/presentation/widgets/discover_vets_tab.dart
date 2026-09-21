import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/format/currency.dart';
import '../../../../core/theme/theme.dart';
import '../../data/vet_discovery_service.dart';
import 'vet_detail_dialog.dart';
import 'vet_map.dart';

/// The "Discover Vets" section of the unified Find Vet feature: filters by
/// location/distance, specialty, consultation mode, availability, emergency
/// support, verification status, fee range and rating, a list of matching
/// doctors, and an optional map view of the same filtered results (this
/// subsumes what the old standalone vet-map screen showed).
class DiscoverVetsTab extends StatefulWidget {
  const DiscoverVetsTab({super.key, this.diseaseContext});

  /// Set when opened from Disease Detection ("mention this to the vet").
  final String? diseaseContext;

  @override
  State<DiscoverVetsTab> createState() => _DiscoverVetsTabState();
}

/// Explicit outcomes of the best-effort location lookup. Previously every
/// failure (denied, denied forever, service disabled, timeout) was swallowed
/// by a bare `catch (_) {}` with no visible sign anything went wrong — a
/// farmer whose GPS was off just silently never got distances or a "near me"
/// map center, with nothing telling them why or how to fix it.
enum _LocationStatus {
  checking,
  granted,
  serviceDisabled,
  denied,
  deniedForever,
  timedOut,
  unavailable,
}

class _DiscoverVetsTabState extends State<DiscoverVetsTab> {
  final _search = TextEditingController();
  Timer? _debounce;

  String? _mode; // null = any
  String _specialty = '';
  bool _available = false;
  bool _emergency = false;
  bool _verified = false;
  double? _maxFee;
  double? _minRating;
  double? _maxDistanceKm;
  // The map is the primary, always-visible view (matching the previous
  // dedicated map screen) — farmers can switch to List view if they prefer.
  bool _showMap = true;
  String? _selectedVetId;

  double? _latitude;
  double? _longitude;
  _LocationStatus _locationStatus = _LocationStatus.checking;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _doctors = const [];
  final MapController _mapController = MapController();
  final Distance _distance = const Distance();

  @override
  void initState() {
    super.initState();
    // The list loads immediately; location is a best-effort background
    // enhancement (unlike the old dedicated map screen, which blocked on
    // it) — it only refines results (distance value/sort/filter) once (if)
    // it resolves, and never delays the first render.
    _load();
    _tryGetLocation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _tryGetLocation() async {
    // Best-effort only: unlike the old dedicated map screen, location is not
    // required to use Discover Vets — filters and the list work without it,
    // just without a distance value/sort. Never blocks the first load. Every
    // outcome sets an explicit status so the UI can say what happened and
    // offer Retry, instead of failing silently. (_locationStatus already
    // defaults to `checking`, so there is nothing to set synchronously here —
    // doing so from initState's call stack, before the first build, is not
    // the right time to call setState.)
    try {
      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled().timeout(const Duration(seconds: 3));
      if (!serviceEnabled) {
        if (mounted) setState(() => _locationStatus = _LocationStatus.serviceDisabled);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locationStatus = _LocationStatus.deniedForever);
        return;
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        if (mounted) setState(() => _locationStatus = _LocationStatus.denied);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      _latitude = pos.latitude;
      _longitude = pos.longitude;
      setState(() => _locationStatus = _LocationStatus.granted);
      try {
        _mapController.move(LatLng(_latitude!, _longitude!), 13);
      } catch (_) {}
      await _load();
    } on TimeoutException {
      if (mounted) setState(() => _locationStatus = _LocationStatus.timedOut);
    } catch (_) {
      if (mounted) setState(() => _locationStatus = _LocationStatus.unavailable);
    }
  }

  void _fitToContent() {
    final points = _points;
    final me = _latitude != null && _longitude != null ? LatLng(_latitude!, _longitude!) : null;
    final pts = <LatLng>[if (me != null) me, ...points.map((p) => p.location)];
    if (pts.length < 2) {
      if (pts.length == 1) {
        try {
          _mapController.move(pts.first, 12);
        } catch (_) {}
      }
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

  /// Never claims "near me" without a real fix — this is purely informational
  /// plus a way forward (Retry, or Open Settings for a permanent denial). The
  /// list and map both still work with no location at all; distances just
  /// won't be shown.
  Widget? _locationBanner() {
    final (String message, bool showSettings) = switch (_locationStatus) {
      _LocationStatus.serviceDisabled => (
          'Location services are turned off, so vets can\'t be sorted by '
              'distance. Enable location on this device and retry.',
          false
        ),
      _LocationStatus.denied => (
          'Location permission was not granted, so distances aren\'t shown. '
              'Allow location access and retry.',
          false
        ),
      _LocationStatus.deniedForever => (
          'Location permission is permanently denied. Enable it in your '
              'device/browser settings to see distances to nearby vets.',
          true
        ),
      _LocationStatus.timedOut => (
          'Getting your location took too long. You can still browse vets '
              'without distances, or retry.',
          false
        ),
      _LocationStatus.unavailable => (
          'Couldn\'t get your location right now. You can still browse vets '
              'without distances, or retry.',
          false
        ),
      _LocationStatus.checking || _LocationStatus.granted => ('', false),
    };
    if (message.isEmpty) return null;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.location_off_outlined, size: 18, color: Colors.orange),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(message, style: const TextStyle(fontSize: 12, color: Colors.black87)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              TextButton(onPressed: _tryGetLocation, child: const Text('Try again')),
              if (showSettings)
                TextButton(
                    onPressed: () => Geolocator.openAppSettings(),
                    child: const Text('Open settings')),
            ]),
          ]),
        ),
      ]),
    );
  }

  void _recenter() {
    if (_latitude != null && _longitude != null) {
      try {
        _mapController.move(LatLng(_latitude!, _longitude!), 14);
      } catch (_) {}
    } else {
      _tryGetLocation();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await VetDiscoveryService.discover(
        search: _search.text,
        mode: _mode,
        specialty: _specialty.isEmpty ? null : _specialty,
        available: _available,
        emergency: _emergency,
        verified: _verified,
        latitude: _latitude,
        longitude: _longitude,
        maxFee: _maxFee,
        minRating: _minRating,
        maxDistanceKm: _maxDistanceKm,
      );
      if (!mounted) return;
      setState(() {
        _doctors = List<Map<String, dynamic>>.from(
            (data['doctors'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _showMap) _fitToContent();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _openDoctor(Map<String, dynamic> doctor) async {
    final booked = await showDialog<bool>(
      context: context,
      builder: (_) => VetDetailDialog(doctorId: '${doctor['id']}'),
    );
    if (booked == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Consultation requested. Track it in My Consultations.')));
      }
      await _load();
    }
  }

  double? _distanceKm(Map<String, dynamic> doctor) {
    if (_latitude != null && _longitude != null &&
        doctor['latitude'] != null && doctor['longitude'] != null) {
      return _distance.as(
        LengthUnit.Kilometer,
        LatLng(_latitude!, _longitude!),
        LatLng((doctor['latitude'] as num).toDouble(), (doctor['longitude'] as num).toDouble()),
      );
    }
    final api = doctor['distance_km'];
    return api == null ? null : (api as num).toDouble();
  }

  Future<void> _openInGoogleMaps(Map<String, dynamic> doctor) async {
    final lat = (doctor['latitude'] as num?)?.toDouble();
    final lng = (doctor['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      _snack('This vet has not saved a map location yet.');
      return;
    }
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok) await launchUrl(uri).catchError((_) => false);
  }

  Future<void> _call(Map<String, dynamic> doctor) async {
    final phone = '${doctor['phone'] ?? ''}'.trim();
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  /// Tapping a map pin shows a quick-action sheet (Call / Open in Google
  /// Maps / full profile+booking) rather than jumping straight into the
  /// heavier detail dialog — matching the previous dedicated map screen's
  /// tap behaviour. List-card taps still go straight to the full dialog.
  void _onMarkerTap(VetPoint point) {
    final doctor = _doctors.firstWhere((d) => '${d['id']}' == point.id, orElse: () => const {});
    if (doctor.isEmpty) return;
    setState(() => _selectedVetId = point.id);
    final km = _distanceKm(doctor);
    final rating = (doctor['rating'] as num?)?.toDouble();
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${doctor['name'] ?? 'Vet'}',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primary)),
                if ('${doctor['clinic'] ?? ''}'.isNotEmpty)
                  Text('${doctor['clinic']}',
                      style: const TextStyle(fontSize: 13, color: AppColors.hint)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.near_me_outlined, size: 15, color: AppColors.hint),
            const SizedBox(width: 4),
            Text(km == null ? 'Distance unavailable' : '${km.toStringAsFixed(1)} km away',
                style: const TextStyle(fontSize: 13, color: AppColors.hint)),
            const Spacer(),
            if (rating != null && rating > 0) ...[
              const Icon(Icons.star, size: 15, color: Colors.amber),
              const SizedBox(width: 3),
              Text(rating.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ]),
          if ('${doctor['address'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.location_on_outlined, size: 15, color: AppColors.hint),
              const SizedBox(width: 4),
              Expanded(
                child: Text('${doctor['address']}',
                    style: const TextStyle(fontSize: 12, color: AppColors.hint)),
              ),
            ]),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _call(doctor);
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
                  _openInGoogleMaps(doctor);
                },
                icon: const Icon(Icons.map_outlined, size: 16),
                label: const Text('Directions'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _openDoctor(doctor);
              },
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('View full profile & book'),
            ),
          ),
        ]),
      ),
    );
  }

  List<VetPoint> get _points => _doctors
      .where((d) => d['latitude'] != null && d['longitude'] != null)
      .map((d) => VetPoint(
            id: '${d['id']}',
            location: LatLng((d['latitude'] as num).toDouble(), (d['longitude'] as num).toDouble()),
            name: '${d['name'] ?? 'Vet'}',
            clinic: '${d['clinic'] ?? ''}',
          ))
      .toList();

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.diseaseContext != null) ...[
            _DiseaseBanner(text: widget.diseaseContext!),
            const SizedBox(height: 12),
          ],
          _filters(),
          const SizedBox(height: 12),
          if (_locationBanner() != null) ...[_locationBanner()!, const SizedBox(height: 12)],
          Row(children: [
            Expanded(
              child: Text(
                _loading ? 'Searching…' : '${_doctors.length} vet(s) found',
                style: const TextStyle(color: AppColors.hint, fontSize: 12),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() => _showMap = !_showMap);
                if (_showMap) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _fitToContent();
                  });
                }
              },
              icon: Icon(_showMap ? Icons.view_list_outlined : Icons.map_outlined, size: 16),
              label: Text(_showMap ? 'List view' : 'Map view'),
            ),
          ]),
          const SizedBox(height: 4),
          if (_showMap) ...[
            if (_points.isNotEmpty)
              ClipRRect(
                borderRadius: AppRadius.lgAll,
                child: SizedBox(
                  height: 320,
                  child: VetMap(
                    controller: _mapController,
                    center: _latitude != null && _longitude != null
                        ? LatLng(_latitude!, _longitude!)
                        : _points.first.location,
                    userLocation:
                        _latitude != null && _longitude != null ? LatLng(_latitude!, _longitude!) : null,
                    vets: _points,
                    selectedVetId: _selectedVetId,
                    onVetTap: _onMarkerTap,
                    onRecenter: _recenter,
                  ),
                ),
              )
            else if (!_loading)
              Container(
                height: 160,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceContainerHighest,
                  borderRadius: AppRadius.lgAll,
                ),
                child: const Text(
                  'No vets with a saved map location match these filters yet.\nTry List view or widen your filters.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.hint, fontSize: 12),
                ),
              ),
          ],
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _ErrorCard(message: _error!, onRetry: _load)
          else if (_doctors.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text('No veterinarians match these filters.',
                    style: TextStyle(color: AppColors.hint)),
              ),
            )
          else
            ..._doctors.map(_doctorCard),
        ],
      ),
    );
  }

  Widget _filters() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerHighest,
        borderRadius: AppRadius.lgAll,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _search,
          onChanged: _onSearchChanged,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search by name, clinic or specialty',
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          onChanged: (v) {
            _specialty = v;
            _onSearchChanged(v);
          },
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.local_hospital_outlined),
            hintText: 'Specialty or poultry focus area',
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _modeChip(null, 'Any mode'),
          _modeChip('online', 'Online'),
          _modeChip('offline', 'In-person'),
          FilterChip(
            label: const Text('Available now'),
            selected: _available,
            onSelected: (v) => setState(() { _available = v; _load(); }),
          ),
          FilterChip(
            label: const Text('Emergency support'),
            selected: _emergency,
            onSelected: (v) => setState(() { _emergency = v; _load(); }),
          ),
          FilterChip(
            label: const Text('Verified only'),
            selected: _verified,
            onSelected: (v) => setState(() { _verified = v; _load(); }),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _dropdownFilter<double?>(
            label: 'Max fee',
            value: _maxFee,
            items: {null: 'Any fee', 500.0: '৳500', 1000.0: '৳1000', 2000.0: '৳2000', 5000.0: '৳5000'},
            onChanged: (v) => setState(() { _maxFee = v; _load(); }),
          )),
          const SizedBox(width: 8),
          Expanded(child: _dropdownFilter<double?>(
            label: 'Min rating',
            value: _minRating,
            items: {null: 'Any rating', 3.0: '3+', 4.0: '4+', 4.5: '4.5+'},
            onChanged: (v) => setState(() { _minRating = v; _load(); }),
          )),
          const SizedBox(width: 8),
          Expanded(child: _dropdownFilter<double?>(
            label: 'Distance',
            value: _maxDistanceKm,
            items: {null: 'Any distance', 10.0: '10 km', 25.0: '25 km', 50.0: '50 km', 100.0: '100 km'},
            onChanged: (v) => setState(() { _maxDistanceKm = v; _load(); }),
          )),
        ]),
      ]),
    );
  }

  Widget _modeChip(String? value, String label) => ChoiceChip(
        label: Text(label),
        selected: _mode == value,
        onSelected: (_) => setState(() { _mode = value; _load(); }),
      );

  Widget _dropdownFilter<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) =>
      DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: items.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)))
            .toList(),
        onChanged: (v) => onChanged(v as T),
      );

  Widget _doctorCard(Map<String, dynamic> doctor) {
    final rating = (doctor['rating'] as num?)?.toDouble() ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openDoctor(doctor),
        borderRadius: AppRadius.lgAll,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: .1),
                child: const Icon(Icons.medical_services_outlined, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text('${doctor['name'] ?? 'Veterinarian'}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                    if (doctor['verified'] == true)
                      const Icon(Icons.verified, color: AppColors.secondary, size: 16),
                  ]),
                  Text('${doctor['specialty'] ?? ''}', style: const TextStyle(color: AppColors.hint)),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(taka((doctor['fee'] as num?) ?? 0)),
              ),
              Chip(
                visualDensity: VisualDensity.compact,
                label: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star, size: 13, color: Color(0xFFFFB300)),
                  const SizedBox(width: 3),
                  Text(rating.toStringAsFixed(1)),
                ]),
              ),
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(doctor['available'] == true ? 'Available now' : 'Offline'),
                backgroundColor: doctor['available'] == true
                    ? AppColors.secondary.withValues(alpha: .15)
                    : null,
              ),
              if (doctor['distance_km'] != null)
                Chip(visualDensity: VisualDensity.compact, label: Text('${doctor['distance_km']} km')),
              if (doctor['emergency'] == true)
                const Chip(visualDensity: VisualDensity.compact, label: Text('Emergency')),
            ]),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _openDoctor(doctor),
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('View & book'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
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

class _DiseaseBanner extends StatelessWidget {
  const _DiseaseBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.07),
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.coronavirus_outlined, size: 18, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text('From disease detection: "$text". Mention this when you contact the vet.',
                style: const TextStyle(fontSize: 12, color: Colors.black87)),
          ),
        ]),
      );
}
