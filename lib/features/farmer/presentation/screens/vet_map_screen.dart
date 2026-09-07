import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:featherflow/core/theme/theme.dart';
import '../../data/directions_service.dart';
import '../../data/vet_discovery_service.dart';
import '../widgets/vet_map.dart';
import '../widgets/farmer_booking_dialog.dart';

class VetMapScreen extends StatefulWidget {
  const VetMapScreen({super.key});

  @override
  State<VetMapScreen> createState() => _VetMapScreenState();
}

class _VetMapScreenState extends State<VetMapScreen> {
  Map<String, dynamic>? _data;
  final MapController _mapController = MapController();

  static const LatLng _fallbackCenter = LatLng(23.8103, 90.4125); // Dhaka
  LatLng? _userLatLng;
  LatLng _center = _fallbackCenter;
  StreamSubscription<Position>? _positionSub;

  int _filter = 0;
  final _searchController = TextEditingController();
  String? _mode;
  bool _verifiedOnly = false;
  bool _loadingLocation = false;
  bool _bookingOpen = false;
  bool _mapView = true;
  String? _error;

  String? _selectedVetId;
  List<LatLng> _route = const [];
  DirectionsResult? _routeInfo;
  String? _routeVetName;

  final _distance = const Distance();

  List<Map<String, dynamic>> get _all =>
      List<Map<String, dynamic>>.from((_data?['doctors'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e)));

  List<Map<String, dynamic>> get _doctors => _all.where((vet) {
        if (_filter == 1) {
          return vet['specialty'].toString().toLowerCase().contains('poultry');
        }
        if (_filter == 2) {
          return vet['emergency'] == true && vet['available'] == true;
        }
        return true;
      }).toList();

  List<VetPoint> get _vetPoints => _doctors
      .where((v) => v['latitude'] != null && v['longitude'] != null)
      .map((v) => VetPoint(
            id: v['id'].toString(),
            location: LatLng((v['latitude'] as num).toDouble(),
                (v['longitude'] as num).toDouble()),
            name: v['name']?.toString() ?? '',
            specialty: v['specialty']?.toString() ?? '',
            available: v['available'] == true,
          ))
      .toList();

  @override
  void initState() {
    super.initState();
    _load();
    _startLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await VetDiscoveryService.discover(
        search: _searchController.text,
        mode: _mode,
        specialty: _filter == 1 ? 'poultry' : null,
        emergency: _filter == 2,
        available: _filter == 2,
        verified: _verifiedOnly,
        latitude: _userLatLng?.latitude,
        longitude: _userLatLng?.longitude,
      );
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
        if (_route.isEmpty) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _fitToContent());
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Frame the map on the farmer plus the vets within ~60 km (far-flung
  /// clinics in other districts would otherwise zoom the map out to nothing).
  void _fitToContent() {
    final user = _userLatLng;
    final near = _vetPoints.where((v) =>
        user == null ||
        _distance.as(LengthUnit.Kilometer, user, v.location) <= 60);
    final pts = <LatLng>[
      if (user != null) user,
      for (final v in near) v.location,
    ];
    if (pts.length < 2) {
      if (user != null) {
        try {
          _mapController.move(user, 12);
        } catch (_) {}
      }
      return;
    }
    try {
      _mapController.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.all(44),
        maxZoom: 13,
      ));
    } catch (_) {}
  }

  // ── location ──────────────────────────────────────────────────────────────
  Future<void> _startLocation() async {
    setState(() => _loadingLocation = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Location services are turned off on this device.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission is required to show vets near you.');
      }
      final p = await Geolocator.getCurrentPosition();
      _applyPosition(p, recenter: true);
      await _load();
      _positionSub?.cancel();
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 25,
        ),
      ).listen((pos) => _applyPosition(pos, recenter: false));
    } catch (e) {
      if (mounted) _message(e.toString());
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  void _applyPosition(Position p, {required bool recenter}) {
    if (!mounted) return;
    setState(() {
      _userLatLng = LatLng(p.latitude, p.longitude);
      if (recenter) _center = _userLatLng!;
    });
    if (recenter) {
      try {
        _mapController.move(_userLatLng!, 13);
      } catch (_) {}
    }
  }

  void _recenterOnUser() {
    final u = _userLatLng;
    if (u == null) {
      _startLocation();
      return;
    }
    setState(() => _center = u);
    try {
      _mapController.move(u, 14);
    } catch (_) {}
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  double? _distanceKm(Map<String, dynamic> vet) {
    if (vet['latitude'] == null || vet['longitude'] == null) return null;
    final vll = LatLng((vet['latitude'] as num).toDouble(),
        (vet['longitude'] as num).toDouble());
    if (_userLatLng != null) {
      return _distance.as(LengthUnit.Kilometer, _userLatLng!, vll);
    }
    final api = vet['distance_km'];
    return api == null ? null : (api as num).toDouble();
  }

  // ── directions ────────────────────────────────────────────────────────────
  Future<void> _getDirections(Map<String, dynamic> vet) async {
    if (vet['latitude'] == null || vet['longitude'] == null) {
      return _message('This vet has not saved a precise location yet.');
    }
    final dest = LatLng((vet['latitude'] as num).toDouble(),
        (vet['longitude'] as num).toDouble());
    final origin = _userLatLng;
    if (origin == null) {
      _message('Getting your location…');
      await _startLocation();
      if (_userLatLng == null) return;
    }
    setState(() {
      _selectedVetId = vet['id'].toString();
      _mapView = true;
    });
    _message('Finding the route…');
    final result = await DirectionsService.route(_userLatLng!, dest);
    if (!mounted) return;
    setState(() {
      _route = result.points;
      _routeInfo = result;
      _routeVetName = vet['name']?.toString();
    });
    _fitRoute(result.points);
  }

  void _clearRoute() => setState(() {
        _route = const [];
        _routeInfo = null;
        _routeVetName = null;
        _selectedVetId = null;
      });

  void _fitRoute(List<LatLng> pts) {
    if (pts.length < 2) return;
    try {
      _mapController.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.all(48),
      ));
    } catch (_) {}
  }

  // ── vet tap sheet ─────────────────────────────────────────────────────────
  void _onVetTap(VetPoint point) {
    final vet = _doctors.firstWhere((v) => v['id'].toString() == point.id,
        orElse: () => <String, dynamic>{});
    if (vet.isEmpty) return;
    setState(() => _selectedVetId = point.id);
    final km = _distanceKm(vet);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _doctorIdentity(vet),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.near_me_outlined, size: 15, color: AppColors.hint),
            const SizedBox(width: 4),
            Text(
              km == null
                  ? 'Distance unavailable'
                  : '${km.toStringAsFixed(1)} km away',
              style: const TextStyle(fontSize: 12, color: AppColors.hint),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _getDirections(vet);
                },
                icon: const Icon(Icons.directions_outlined, size: 16),
                label: const Text('Directions'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _profile(vet);
                },
                icon: const Icon(Icons.person_outline, size: 16),
                label: const Text('Profile'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _request(vet);
              },
              icon: const Icon(Icons.event_available_outlined, size: 16),
              label: const Text('Book consultation'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _profile(Map<String, dynamic> vet) async {
    Map<String, dynamic> details;
    try {
      details = await VetDiscoveryService.detail(vet['id'].toString());
    } catch (e) {
      return _message(e.toString());
    }
    if (!mounted) return;
    final slots = List<Map<String, dynamic>>.from(
      (details['availability_slots'] as List? ?? const [])
          .map((x) => Map<String, dynamic>.from(x as Map)),
    );
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(details['name'].toString()),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _detail(Icons.verified_outlined,
                    '${details['degree']} • ${details['experience_years']} years'),
                _detail(Icons.medical_services_outlined,
                    details['specialty'].toString()),
                _detail(Icons.local_hospital_outlined,
                    details['clinic'].toString()),
                _detail(
                    Icons.location_on_outlined, details['address'].toString()),
                _detail(Icons.star_outline,
                    '${details['rating']} rating (${details['total_ratings']} reviews) • ৳${details['fee']}'),
                _detail(Icons.school_outlined,
                    '${details['university']} • Graduated ${details['graduation_year']}'),
                _detail(
                    Icons.schedule_outlined,
                    slots.isEmpty
                        ? 'No recurring availability published'
                        : '${slots.length} weekly availability slots'),
                ...slots.take(5).map((slot) => Padding(
                      padding: const EdgeInsets.only(left: 26, bottom: 4),
                      child: Text(
                        '${days[(slot['weekday'] as num).toInt()]}: ${slot['start_time']}–${slot['end_time']} (${slot['mode']})',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.hint),
                      ),
                    )),
                if (details['focus_area'].toString().isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(details['focus_area'].toString())),
              ])),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _request(details);
            },
            child: const Text('Request Consultation'),
          ),
        ],
      ),
    );
  }

  Widget _detail(IconData icon, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: AppColors.secondary),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ]),
      );

  Future<void> _request(Map<String, dynamic> vet,
      {String? preferredMode}) async {
    if (_bookingOpen) return;
    setState(() => _bookingOpen = true);
    bool? accepted;
    try {
      accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        builder: (_) =>
            FarmerBookingDialog(vet: vet, preferredMode: preferredMode),
      );
    } finally {
      if (mounted) setState(() => _bookingOpen = false);
    }
    if (accepted == true) {
      _message('Consultation request sent to ${vet['name']}.');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = Map<String, dynamic>.from(_data?['summary'] as Map? ?? {});
    final closest = _doctors.isEmpty ? null : _doctors.first;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/farmer')),
        title: const Text('Featherflow Vet Map',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
              icon: const Icon(Icons.home, color: Colors.white),
              onPressed: () => context.go('/farmer'))
        ],
      ),
      body: AbsorbPointer(
        absorbing: _bookingOpen,
        child: _data == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!),
                        TextButton(
                            onPressed: _load, child: const Text('Retry'))
                      ]))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      const Text('Get vet help nearby',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary)),
                      const SizedBox(height: 4),
                      const Text('Live map of verified vets around you',
                          style:
                              TextStyle(fontSize: 14, color: AppColors.hint)),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _load(),
                        decoration: InputDecoration(
                          hintText:
                              'Search doctor, specialty, clinic or location',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                            onPressed: _load,
                            icon: const Icon(Icons.arrow_forward),
                          ),
                          border: const OutlineInputBorder(
                              borderRadius: AppRadius.mdAll),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: DropdownButtonFormField<String?>(
                          initialValue: _mode,
                          decoration: const InputDecoration(
                            labelText: 'Consultation mode',
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: null, child: Text('Any mode')),
                            DropdownMenuItem(
                                value: 'online', child: Text('Online')),
                            DropdownMenuItem(
                                value: 'offline', child: Text('Clinic visit')),
                          ],
                          onChanged: (value) {
                            setState(() => _mode = value);
                            _load();
                          },
                        )),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Verified'),
                          selected: _verifiedOnly,
                          onSelected: (value) {
                            setState(() => _verifiedOnly = value);
                            _load();
                          },
                        ),
                      ]),
                      const SizedBox(height: AppSpacing.md),
                      Row(children: [
                        _stat('${summary['nearby_doctors'] ?? 0}',
                            'Nearby Doctors', Icons.person_outline),
                        const SizedBox(width: 8),
                        _stat('${summary['active_clinics'] ?? 0}',
                            'Active Clinics', Icons.local_hospital_outlined),
                        const SizedBox(width: 8),
                        _stat('${summary['available_now'] ?? 0}',
                            'Available Now', Icons.bolt_outlined),
                      ]),
                      const SizedBox(height: AppSpacing.md),
                      Row(children: [
                        Expanded(
                            child: OutlinedButton.icon(
                          onPressed:
                              _loadingLocation ? null : _recenterOnUser,
                          icon: _loadingLocation
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.my_location, size: 16),
                          label: Text(_userLatLng == null
                              ? 'Use my location'
                              : 'Recenter on me'),
                        )),
                        const SizedBox(width: 8),
                        Expanded(
                            child: ElevatedButton.icon(
                          onPressed:
                              closest == null ? null : () => _request(closest),
                          icon:
                              const Icon(Icons.video_call_outlined, size: 16),
                          label: const Text('Quick Consult'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white),
                        )),
                      ]),
                      const SizedBox(height: AppSpacing.md),
                      Row(children: [
                        Expanded(
                          child: SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(
                                  value: true,
                                  icon: Icon(Icons.map_outlined, size: 16),
                                  label: Text('Map')),
                              ButtonSegment(
                                  value: false,
                                  icon:
                                      Icon(Icons.view_list_outlined, size: 16),
                                  label: Text('List')),
                            ],
                            selected: {_mapView},
                            showSelectedIcon: false,
                            onSelectionChanged: (s) =>
                                setState(() => _mapView = s.first),
                          ),
                        ),
                      ]),
                      const SizedBox(height: AppSpacing.sm),
                      if (_mapView) ...[
                        ClipRRect(
                          borderRadius: AppRadius.lgAll,
                          child: SizedBox(
                            height: 320,
                            child: VetMap(
                              controller: _mapController,
                              center: _center,
                              userLocation: _userLatLng,
                              vets: _vetPoints,
                              selectedVetId: _selectedVetId,
                              route: _route,
                              onVetTap: _onVetTap,
                              onRecenter: _recenterOnUser,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (_routeInfo != null)
                          _RouteBanner(
                            vetName: _routeVetName ?? 'vet',
                            info: _routeInfo!,
                            onClear: _clearRoute,
                          )
                        else
                          Row(children: [
                            const Icon(Icons.place_outlined,
                                size: 13, color: AppColors.hint),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _userLatLng == null
                                    ? '${_vetPoints.length} vet(s) on the map • enable location to see your position'
                                    : '${_vetPoints.length} vet(s) nearby • tap a pin for directions & booking',
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.hint),
                              ),
                            ),
                          ]),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                          spacing: 8,
                          children: ['Distance', 'Specialty', 'Emergency Only']
                              .asMap()
                              .entries
                              .map((e) => ChoiceChip(
                                    label: Text(e.value),
                                    selected: _filter == e.key,
                                    selectedColor: AppColors.primary,
                                    labelStyle: TextStyle(
                                        color: _filter == e.key
                                            ? Colors.white
                                            : AppColors.hint),
                                    onSelected: (_) {
                                      setState(() => _filter = e.key);
                                      _load();
                                    },
                                  ))
                              .toList()),
                      if (closest != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        _closestCard(closest),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      const Text('Registered Doctors',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                      const SizedBox(height: 8),
                      ..._doctors.map(_doctorCard),
                      if (_doctors.isEmpty)
                        const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                                child: Text('No vets match this filter.'))),
                    ]),
              ),
      ),
    );
  }

  Widget _stat(String value, String label, IconData icon) => Expanded(
          child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: .07),
            borderRadius: AppRadius.mdAll,
            border:
                Border.all(color: AppColors.secondary.withValues(alpha: .18))),
        child: Column(children: [
          Icon(icon, color: AppColors.primary, size: 18),
          Text(value,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary)),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9, color: AppColors.hint))
        ]),
      ));

  Widget _closestCard(Map<String, dynamic> vet) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: _cardDecoration,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Closest Available Vet',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.secondary)),
          const SizedBox(height: 10),
          _doctorIdentity(vet),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: OutlinedButton(
                    onPressed: () => _getDirections(vet),
                    child: const Text('Directions'))),
            const SizedBox(width: 8),
            Expanded(
                child: OutlinedButton(
                    onPressed: () => _profile(vet),
                    child: const Text('Profile'))),
            const SizedBox(width: 8),
            Expanded(
                child: ElevatedButton(
                    onPressed: () => _request(vet),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white),
                    child: const Text('Book'))),
          ]),
        ]),
      );

  Widget _doctorCard(Map<String, dynamic> vet) {
    final km = _distanceKm(vet);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: _cardDecoration,
      child: Row(children: [
        Expanded(flex: 4, child: _doctorIdentity(vet)),
        Text(km == null ? '—' : '${km.toStringAsFixed(1)} km',
            style: const TextStyle(fontSize: 12, color: AppColors.hint)),
        const SizedBox(width: 10),
        PopupMenuButton<String>(
          tooltip: 'Vet actions',
          onSelected: (x) {
            if (x == 'profile') _profile(vet);
            if (x == 'directions') _getDirections(vet);
            if (x == 'online') _request(vet, preferredMode: 'online');
            if (x == 'offline') _request(vet, preferredMode: 'offline');
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
                value: 'profile', child: Text('View profile')),
            const PopupMenuItem(
                value: 'directions', child: Text('Directions on map')),
            if (vet['mode'] != 'offline')
              const PopupMenuItem(
                  value: 'online', child: Text('Online consultation')),
            if (vet['mode'] != 'online')
              const PopupMenuItem(
                  value: 'offline', child: Text('Schedule clinic visit')),
          ],
        ),
      ]),
    );
  }

  Widget _doctorIdentity(Map<String, dynamic> vet) => Row(children: [
        CircleAvatar(
          backgroundColor: AppColors.secondary.withValues(alpha: .14),
          child: Text(
              vet['name'].toString().isEmpty ? 'V' : vet['name'].toString()[0],
              style: const TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(
                child: Text(vet['name'].toString(),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary))),
            if (vet['verified'] == true)
              const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.verified,
                      size: 15, color: AppColors.secondary)),
          ]),
          Text(vet['specialty'].toString(),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.hint)),
          Text(
              vet['available'] == true
                  ? '● Available • ${vet['mode']}'
                  : 'Unavailable',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: vet['available'] == true
                      ? AppColors.secondary
                      : Colors.orange)),
        ])),
      ]);

  BoxDecoration get _cardDecoration => BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.secondary.withValues(alpha: .18)),
        boxShadow: [
          BoxShadow(
              color: AppColors.primary.withValues(alpha: .05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      );
}

class _RouteBanner extends StatelessWidget {
  final String vetName;
  final DirectionsResult info;
  final VoidCallback onClear;

  const _RouteBanner({
    required this.vetName,
    required this.info,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        const Icon(Icons.directions_car_filled_outlined,
            size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'To $vetName · ${info.distanceKm.toStringAsFixed(1)} km · '
            '~${info.durationMin} min${info.approximate ? ' (approx.)' : ''}',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary),
          ),
        ),
        InkWell(
          onTap: onClear,
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.close, size: 16, color: AppColors.primary),
          ),
        ),
      ]),
    );
  }
}
