import 'package:flutter/material.dart';

import '../../../../core/theme/theme.dart';
import '../../data/vet_discovery_service.dart';
import 'vet_booking_dialog.dart';

/// Full doctor-detail view opened from a card in Discover Vets: profile,
/// verification/status, specialties, consultation modes, fee, published
/// weekly availability and recent reviews, with a "Book consultation" action
/// that opens [VetBookingDialog].
class VetDetailDialog extends StatefulWidget {
  const VetDetailDialog({super.key, required this.doctorId});

  final String doctorId;

  @override
  State<VetDetailDialog> createState() => _VetDetailDialogState();
}

class _VetDetailDialogState extends State<VetDetailDialog> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _doctor;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await VetDiscoveryService.detail(widget.doctorId);
      if (mounted) setState(() { _doctor = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _book() async {
    final doctor = _doctor;
    if (doctor == null) return;
    final booked = await showDialog<bool>(
      context: context,
      builder: (_) => VetBookingDialog(doctor: doctor),
    );
    if (booked == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 800),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
            child: Row(children: [
              const Icon(Icons.medical_information_outlined, color: AppColors.primary),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Veterinarian profile',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!),
                        TextButton(onPressed: _load, child: const Text('Retry')),
                      ]))
                    : _content(_doctor!),
          ),
        ]),
      ),
    );
  }

  Widget _content(Map<String, dynamic> d) {
    final slots = List<Map<String, dynamic>>.from(
        (d['availability_slots'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    final reviews = List<Map<String, dynamic>>.from(
        (d['recent_reviews'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    final rating = (d['rating'] as num?)?.toDouble() ?? 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.primary.withValues(alpha: .1),
            backgroundImage: (d['photo_url'] as String?)?.isNotEmpty == true
                ? NetworkImage(d['photo_url'])
                : null,
            child: (d['photo_url'] as String?)?.isNotEmpty == true
                ? null
                : const Icon(Icons.medical_services_outlined, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text('${d['name'] ?? 'Veterinarian'}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                if (d['verified'] == true)
                  const Icon(Icons.verified, color: AppColors.secondary, size: 18),
              ]),
              Text('${d['degree'] ?? ''} • ${d['specialty'] ?? ''}',
                  style: const TextStyle(color: AppColors.hint)),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.star, color: Color(0xFFFFB300), size: 16),
                const SizedBox(width: 3),
                Text('${rating.toStringAsFixed(1)} (${d['total_ratings'] ?? 0} ratings)'),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Chip(label: Text('Fee ৳${d['fee'] ?? 0}')),
          Chip(label: Text('Mode: ${_modeLabel(d['mode'])}')),
          Chip(
            label: Text(d['available'] == true ? 'Available now' : 'Currently offline'),
            backgroundColor: d['available'] == true
                ? AppColors.secondary.withValues(alpha: .15)
                : AppColors.errorContainer,
          ),
          if (d['emergency'] == true) const Chip(label: Text('Emergency support')),
          if (d['distance_km'] != null) Chip(label: Text('${d['distance_km']} km away')),
        ]),
        const SizedBox(height: 18),
        _section('Practice', [
          _line('Clinic', d['clinic']),
          _line('Address', d['address']),
          _line('Focus area', d['focus_area']),
          _line('Experience', '${d['experience_years'] ?? 0} years'),
        ]),
        _section('Credentials', [
          _line('University', d['university']),
          _line('Graduation year', d['graduation_year']),
          _line('License authority', d['license_authority']),
          _line('Prescription authority', d['prescription_authority'] == true ? 'Yes' : 'No'),
        ]),
        _section(
          'Weekly availability',
          slots.isEmpty
              ? [const Text('No published availability yet.', style: TextStyle(color: AppColors.hint))]
              : slots
                  .map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                            '${_weekdays[(s['weekday'] as num).toInt().clamp(0, 6)]}: '
                            '${s['start_time']}–${s['end_time']} (${_modeLabel(s['mode'])})'),
                      ))
                  .toList(),
        ),
        _section(
          'Recent reviews',
          reviews.isEmpty
              ? [const Text('No reviews yet.', style: TextStyle(color: AppColors.hint))]
              : reviews
                  .map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            ...List.generate(
                              5,
                              (i) => Icon(
                                i < ((r['rating'] as num?)?.toInt() ?? 0)
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                size: 16,
                                color: const Color(0xFFFFB300),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('${r['farmer_name'] ?? ''} • ${r['date'] ?? ''}',
                                style: const TextStyle(color: AppColors.hint, fontSize: 12)),
                          ]),
                          if ('${r['review'] ?? ''}'.trim().isNotEmpty)
                            Text('“${r['review']}”'),
                        ]),
                      ))
                  .toList(),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _book,
            icon: const Icon(Icons.event_available_outlined),
            label: const Text('Book consultation'),
          ),
        ),
      ]),
    );
  }

  String _modeLabel(Object? mode) => switch (mode) {
        'online' => 'Online',
        'offline' => 'In-person',
        'both' => 'Online & In-person',
        _ => '$mode',
      };

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const Divider(),
          ...children,
        ]),
      );

  Widget _line(String label, Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == 'null') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: '$label: ', style: const TextStyle(color: AppColors.hint)),
        TextSpan(text: text),
      ])),
    );
  }
}
