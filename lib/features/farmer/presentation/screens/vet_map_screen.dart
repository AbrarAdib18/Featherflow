import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:featherflow/core/theme/theme.dart';
import '../../data/farm_management_service.dart';
import '../widgets/google_map_embed.dart';

class VetMapScreen extends StatefulWidget {
  const VetMapScreen({super.key});

  @override
  State<VetMapScreen> createState() => _VetMapScreenState();
}

class _VetMapScreenState extends State<VetMapScreen> {
  Map<String, dynamic>? _data;
  double _latitude = 23.8103;
  double _longitude = 90.4125;
  String _mapLabel = 'Dhaka';
  int _filter = 0;
  bool _loadingLocation = false;
  String? _error;

  List<Map<String, dynamic>> get _all =>
      List<Map<String, dynamic>>.from((_data?['doctors'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e)));

  List<Map<String, dynamic>> get _doctors => _all.where((vet) {
        if (_filter == 1)
          return vet['specialty'].toString().toLowerCase().contains('poultry');
        if (_filter == 2)
          return vet['emergency'] == true && vet['available'] == true;
        return true;
      }).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await FarmManagementService.get('consultations/vets');
      if (mounted)
        setState(() {
          _data = data;
          _error = null;
        });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _locate() async {
    setState(() => _loadingLocation = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission is required to find nearby vets.');
      }
      final p = await Geolocator.getCurrentPosition();
      _latitude = p.latitude;
      _longitude = p.longitude;
      _mapLabel = 'Your current location';
      final data = await FarmManagementService.get(
          'consultations/vets?latitude=${p.latitude}&longitude=${p.longitude}');
      if (mounted) setState(() => _data = data);
    } catch (e) {
      _message(e.toString());
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  void _message(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _directions(Map<String, dynamic> vet) async {
    final lat = vet['latitude'];
    final lng = vet['longitude'];
    if (lat == null || lng == null)
      return _message('Location is unavailable for this vet.');
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _message('Could not open Google Maps.');
    }
  }

  Future<void> _profile(Map<String, dynamic> vet) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(vet['name'].toString()),
        content: SizedBox(
          width: 420,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detail(Icons.verified_outlined,
                    '${vet['degree']} • ${vet['experience_years']} years'),
                _detail(Icons.medical_services_outlined,
                    vet['specialty'].toString()),
                _detail(
                    Icons.local_hospital_outlined, vet['clinic'].toString()),
                _detail(Icons.location_on_outlined, vet['address'].toString()),
                _detail(Icons.star_outline,
                    '${vet['rating']} rating • ৳${vet['fee']}'),
                if (vet['focus_area'].toString().isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(vet['focus_area'].toString())),
              ]),
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
              _request(vet);
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
    String mode =
        preferredMode ?? (vet['mode'] == 'offline' ? 'offline' : 'online');
    String urgency = 'routine';
    DateTime date = DateTime.now();
    TimeOfDay time =
        TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1)));
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
                title: const Text('Request Consultation'),
                content: SizedBox(
                    width: 420,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<String>(
                        initialValue: mode,
                        decoration: const InputDecoration(
                            labelText: 'Consultation mode'),
                        items: ['online', 'offline']
                            .where((x) =>
                                vet['mode'] == 'both' || vet['mode'] == x)
                            .map((x) => DropdownMenuItem(
                                value: x,
                                child: Text(x == 'online'
                                    ? 'Online consultation'
                                    : 'Clinic visit')))
                            .toList(),
                        onChanged: (x) => setLocal(() => mode = x!),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: urgency,
                        decoration: const InputDecoration(labelText: 'Urgency'),
                        items: const [
                          'routine',
                          'moderate',
                          'urgent',
                          'emergency'
                        ]
                            .map((x) =>
                                DropdownMenuItem(value: x, child: Text(x)))
                            .toList(),
                        onChanged: (x) => setLocal(() => urgency = x!),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                            child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today_outlined,
                              size: 16),
                          label: Text('${date.day}/${date.month}/${date.year}'),
                          onPressed: () async {
                            final picked = await showDatePicker(
                                context: ctx,
                                initialDate: date,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 90)));
                            if (picked != null) setLocal(() => date = picked);
                          },
                        )),
                        const SizedBox(width: 8),
                        Expanded(
                            child: OutlinedButton.icon(
                          icon: const Icon(Icons.schedule_outlined, size: 16),
                          label: Text(time.format(ctx)),
                          onPressed: () async {
                            final picked = await showTimePicker(
                                context: ctx, initialTime: time);
                            if (picked != null) setLocal(() => time = picked);
                          },
                        )),
                      ]),
                      const SizedBox(height: 10),
                      Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Consultation fee: ৳${vet['fee']}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700))),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Send Request'),
                  ),
                ],
              )),
    );
    if (accepted != true) return;
    try {
      final d =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final t =
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      await FarmManagementService.post('consultations', {
        'doctor_id': vet['id'],
        'mode': mode,
        'urgency': urgency,
        'appointment_date': d,
        'appointment_time': t,
      });
      _message('Consultation request sent to ${vet['name']}.');
    } catch (e) {
      _message(e.toString());
    }
  }

  void _showOnMap(Map<String, dynamic> vet) {
    if (vet['latitude'] == null || vet['longitude'] == null) {
      return _message('This doctor has not saved a precise map location yet.');
    }
    setState(() {
      _latitude = (vet['latitude'] as num).toDouble();
      _longitude = (vet['longitude'] as num).toDouble();
      _mapLabel = vet['name'].toString();
    });
    _message('Showing ${vet['name']} on Google Maps.');
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
            onPressed: () => Navigator.of(context).pop()),
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
      body: _data == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!),
                      TextButton(onPressed: _load, child: const Text('Retry'))
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
                    const Text('Find verified vets and clinics fast',
                        style: TextStyle(fontSize: 14, color: AppColors.hint)),
                    const SizedBox(height: AppSpacing.md),
                    Row(children: [
                      _stat('${summary['nearby_doctors'] ?? 0}',
                          'Nearby Doctors', Icons.person_outline),
                      const SizedBox(width: 8),
                      _stat('${summary['active_clinics'] ?? 0}',
                          'Active Clinics', Icons.local_hospital_outlined),
                      const SizedBox(width: 8),
                      _stat('${summary['available_now'] ?? 0}', 'Available Now',
                          Icons.bolt_outlined),
                    ]),
                    const SizedBox(height: AppSpacing.md),
                    Row(children: [
                      Expanded(
                          child: OutlinedButton.icon(
                        onPressed: _loadingLocation ? null : _locate,
                        icon: _loadingLocation
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.my_location, size: 16),
                        label: const Text('Find Nearby Vets'),
                      )),
                      const SizedBox(width: 8),
                      Expanded(
                          child: ElevatedButton.icon(
                        onPressed:
                            closest == null ? null : () => _request(closest),
                        icon: const Icon(Icons.video_call_outlined, size: 16),
                        label: const Text('Request Consultation'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white),
                      )),
                    ]),
                    const SizedBox(height: AppSpacing.md),
                    ClipRRect(
                      borderRadius: AppRadius.lgAll,
                      child: SizedBox(
                        height: 300,
                        child: GoogleMapEmbed(
                          latitude: _latitude,
                          longitude: _longitude,
                          label: _mapLabel,
                        ),
                      ),
                    ),
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
                                  onSelected: (_) =>
                                      setState(() => _filter = e.key),
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
                    onPressed: () => _profile(vet),
                    child: const Text('View Profile'))),
            const SizedBox(width: 8),
            Expanded(
                child: ElevatedButton(
                    onPressed: () => _request(vet),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white),
                    child: const Text('Request'))),
          ]),
        ]),
      );

  Widget _doctorCard(Map<String, dynamic> vet) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: _cardDecoration,
        child: Row(children: [
          Expanded(flex: 4, child: _doctorIdentity(vet)),
          Text(
              vet['distance_km'] == null
                  ? 'Location set'
                  : '${vet['distance_km']} km',
              style: const TextStyle(fontSize: 12, color: AppColors.hint)),
          const SizedBox(width: 10),
          PopupMenuButton<String>(
            tooltip: 'Vet actions',
            onSelected: (x) {
              if (x == 'profile') _profile(vet);
              if (x == 'map') _showOnMap(vet);
              if (x == 'online') _request(vet, preferredMode: 'online');
              if (x == 'offline') _request(vet, preferredMode: 'offline');
              if (x == 'directions') _directions(vet);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'profile', child: Text('View profile')),
              const PopupMenuItem(
                  value: 'map', child: Text('Show precise location')),
              if (vet['mode'] != 'offline')
                const PopupMenuItem(
                    value: 'online', child: Text('Online consultation')),
              if (vet['mode'] != 'online')
                const PopupMenuItem(
                    value: 'offline', child: Text('Schedule clinic visit')),
              const PopupMenuItem(
                  value: 'directions', child: Text('Google Maps directions')),
            ],
          ),
        ]),
      );

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
