import 'package:flutter/material.dart';

import '../../../../core/theme/theme.dart';
import '../../data/vet_discovery_service.dart';

/// The consultation booking dialog opened from a vet's detail view inside
/// "Find Vet > Discover Vets". Reuses the existing, already-validated backend
/// booking pipeline (`POST /api/consultations/`) end to end — this dialog only
/// adds client-side guardrails (required fields, date range, only-published
/// times selectable) so a farmer sees a clear error before submitting rather
/// than only after a 400/409 comes back.
class VetBookingDialog extends StatefulWidget {
  const VetBookingDialog({super.key, required this.doctor});

  /// The doctor row from the discovery/detail endpoint (`_doctor_row`).
  final Map<String, dynamic> doctor;

  @override
  State<VetBookingDialog> createState() => _VetBookingDialogState();
}

class _VetBookingDialogState extends State<VetBookingDialog> {
  bool _loadingOptions = true;
  String? _optionsError;
  List<Map<String, dynamic>> _farms = const [];
  // Server-owned bird-type vocabulary from booking-options (farms.constants) —
  // replaces the unconstrained breed text field that could never match a
  // feeding guideline for a hand-typed value.
  List<Map<String, dynamic>> _birdTypes = const [];

  String? _farmId;
  String? _flockId;
  String _mode = 'online';
  String _urgency = 'routine';
  DateTime? _date;
  String? _time;
  // A preferred slot is optional — availability is informational only, so a
  // farmer can submit with no date/time at all and let the doctor propose one.
  bool _requestAnyTime = false;
  List<String> _availableTimes = const [];
  bool _loadingTimes = false;

  final _symptoms = TextEditingController();
  final _mortality = TextEditingController(text: '0');
  final _birdAgeWeeks = TextEditingController();
  String? _birdType;
  final _flockCount = TextEditingController();
  final _farmerNotes = TextEditingController();
  final _feedNotes = TextEditingController();
  final _vaccineHistory = TextEditingController();
  final _biosecurityNotes = TextEditingController();

  bool _submitting = false;
  String? _submitError;

  bool get _doctorSupportsEmergency => widget.doctor['emergency'] == true;
  String get _doctorMode => (widget.doctor['mode'] ?? 'both').toString();

  List<String> get _availableModes {
    if (_doctorMode == 'both') return const ['online', 'offline'];
    return [_doctorMode];
  }

  Map<String, dynamic>? get _selectedFarm =>
      _farms.where((f) => f['id'] == _farmId).cast<Map<String, dynamic>?>().firstOrNull;

  List<Map<String, dynamic>> get _flocksForSelectedFarm =>
      List<Map<String, dynamic>>.from((_selectedFarm?['flocks'] as List?) ?? const []);

  @override
  void initState() {
    super.initState();
    _mode = _availableModes.first;
    _loadOptions();
  }

  @override
  void dispose() {
    _symptoms.dispose();
    _mortality.dispose();
    _birdAgeWeeks.dispose();
    _flockCount.dispose();
    _farmerNotes.dispose();
    _feedNotes.dispose();
    _vaccineHistory.dispose();
    _biosecurityNotes.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loadingOptions = true;
      _optionsError = null;
    });
    try {
      final data = await VetDiscoveryService.bookingOptions('${widget.doctor['id']}');
      if (!mounted) return;
      setState(() {
        _farms = List<Map<String, dynamic>>.from(
            (data['farms'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
        _birdTypes = List<Map<String, dynamic>>.from(
            (data['bird_types'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
        // Preserve a farm the caller already picked (e.g. reopening this
        // dialog after a back-navigation) instead of always resetting to the
        // first one.
        if (_farmId == null || !_farms.any((f) => f['id'] == _farmId)) {
          _farmId = _farms.isNotEmpty ? '${_farms.first['id']}' : null;
        }
        _loadingOptions = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _optionsError = e.toString();
          _loadingOptions = false;
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      helpText: 'Select appointment date',
    );
    if (picked == null) return;
    setState(() {
      _date = picked;
      _time = null;
      _availableTimes = const [];
    });
    await _loadTimes();
  }

  Future<void> _loadTimes() async {
    if (_date == null || _farmId == null) return;
    setState(() => _loadingTimes = true);
    try {
      final data = await VetDiscoveryService.bookingOptions(
        '${widget.doctor['id']}',
        date: _date,
        mode: _mode,
      );
      if (!mounted) return;
      setState(() {
        _availableTimes = List<String>.from(data['available_times'] as List? ?? const []);
        _loadingTimes = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingTimes = false;
          _submitError = e.toString();
        });
      }
    }
  }

  List<String> _parsedSymptoms() => _symptoms.text
      .split(RegExp(r'[\n,]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  String? _clientValidationError() {
    if (_farmId == null) return 'Select a farm.';
    // A preferred slot is optional. Requesting one still requires both halves —
    // a lone date or time can't be scheduled or shown to the doctor.
    if (!_requestAnyTime) {
      if (_date == null) return 'Select an appointment date, or request any available time.';
      if (_time == null) return 'Select an available time, or request any available time.';
    }
    if (_parsedSymptoms().isEmpty) return 'Describe at least one symptom.';
    if (_flockId == null) {
      if (_birdAgeWeeks.text.trim().isEmpty ||
          _birdType == null ||
          _flockCount.text.trim().isEmpty) {
        return 'Enter bird age, bird type and flock count, or select a flock.';
      }
    }
    final mortality = int.tryParse(_mortality.text.trim()) ?? 0;
    final flockCount = _flockId != null
        ? (_flocksForSelectedFarm
                .where((f) => f['id'] == _flockId)
                .cast<Map<String, dynamic>?>()
                .firstOrNull?['count'] as num?)
            ?.toInt()
        : int.tryParse(_flockCount.text.trim());
    if (flockCount != null && mortality > flockCount) {
      return 'Mortality cannot exceed the flock count.';
    }
    return null;
  }

  Future<void> _submit() async {
    final clientError = _clientValidationError();
    if (clientError != null) {
      setState(() => _submitError = clientError);
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      String? appointmentDate;
      if (!_requestAnyTime && _date != null) {
        final year = _date!.year.toString().padLeft(4, '0');
        final month = _date!.month.toString().padLeft(2, '0');
        final day = _date!.day.toString().padLeft(2, '0');
        appointmentDate = '$year-$month-$day';
      }
      await VetDiscoveryService.book({
        'doctor_id': widget.doctor['id'],
        'farm_id': _farmId,
        if (_flockId != null) 'flock_id': _flockId,
        'mode': _mode,
        'urgency': _urgency,
        if (appointmentDate != null) 'appointment_date': appointmentDate,
        if (appointmentDate != null) 'appointment_time': _time,
        'symptoms': _parsedSymptoms(),
        'mortality_count': int.tryParse(_mortality.text.trim()) ?? 0,
        if (_flockId == null) 'bird_age_weeks': int.tryParse(_birdAgeWeeks.text.trim()) ?? 0,
        if (_flockId == null) 'breed': _birdType ?? '',
        if (_flockId == null) 'flock_count': int.tryParse(_flockCount.text.trim()) ?? 1,
        if (_farmerNotes.text.trim().isNotEmpty) 'farmer_notes': _farmerNotes.text.trim(),
        if (_feedNotes.text.trim().isNotEmpty) 'feed_notes': _feedNotes.text.trim(),
        if (_vaccineHistory.text.trim().isNotEmpty) 'vaccine_history': _vaccineHistory.text.trim(),
        if (_biosecurityNotes.text.trim().isNotEmpty) 'biosecurity_notes': _biosecurityNotes.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitError = _humanizeBookingError(e);
        });
      }
    }
  }

  String _humanizeBookingError(Object error) {
    // FarmManagementService surfaces the server's JSON body message when
    // available; fall back to the raw exception text otherwise.
    final text = error.toString();
    return text.replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 780),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
            child: Row(children: [
              const Icon(Icons.event_available_outlined, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Book ${widget.doctor['name'] ?? 'consultation'}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loadingOptions
                ? const Center(child: CircularProgressIndicator())
                : _optionsError != null
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_optionsError!),
                        TextButton(onPressed: _loadOptions, child: const Text('Retry')),
                      ]))
                    : _form(),
          ),
        ]),
      ),
    );
  }

  Widget _form() {
    final flocks = _flocksForSelectedFarm;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_farms.isEmpty)
          const Text(
            'You have no active farm on file yet. Add a farm in Cost Management before booking.',
            style: TextStyle(color: AppColors.error),
          )
        else ...[
          const Text('Farm', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _farmId,
            isExpanded: true,
            items: _farms
                .map((f) => DropdownMenuItem(value: '${f['id']}', child: Text('${f['name']}')))
                .toList(),
            onChanged: (v) => setState(() {
              _farmId = v;
              _flockId = null;
            }),
          ),
          const SizedBox(height: 14),
          const Text('Flock (optional)', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            initialValue: _flockId,
            isExpanded: true,
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('No specific flock')),
              ...flocks.map((f) => DropdownMenuItem<String?>(
                    value: '${f['id']}',
                    child: Text('${f['name']} • ${f['breed']} • ${f['count']} birds'),
                  )),
            ],
            onChanged: (v) => setState(() => _flockId = v),
          ),
          if (_flockId == null) ...[
            const SizedBox(height: 14),
            const Text('Since no flock is selected, enter the basics manually:',
                style: TextStyle(color: AppColors.hint, fontSize: 12)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _birdAgeWeeks,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Bird age (weeks)'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _birdType,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Bird type'),
                  items: _birdTypes
                      .map((t) => DropdownMenuItem(
                          value: '${t['value']}', child: Text('${t['label']}')))
                      .toList(),
                  onChanged: (v) => setState(() => _birdType = v),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _flockCount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Flock count'),
            ),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: _labeled(
                'Consultation mode',
                DropdownButtonFormField<String>(
                  initialValue: _mode,
                  items: _availableModes
                      .map((m) => DropdownMenuItem(
                          value: m, child: Text(m == 'online' ? 'Online' : 'In-person')))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _mode = v;
                      _time = null;
                      _availableTimes = const [];
                    });
                    _loadTimes();
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _labeled(
                'Urgency',
                DropdownButtonFormField<String>(
                  initialValue: _urgency,
                  items: [
                    const DropdownMenuItem(value: 'routine', child: Text('Routine')),
                    const DropdownMenuItem(value: 'moderate', child: Text('Moderate')),
                    const DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                    DropdownMenuItem(
                      value: 'emergency',
                      enabled: _doctorSupportsEmergency,
                      child: Text(_doctorSupportsEmergency
                          ? 'Emergency'
                          : 'Emergency (not offered)'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _urgency = v ?? _urgency),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          const Text('Preferred date & time (optional)',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          const Text(
              'The doctor can accept your request at any time and propose a '
              'slot — you do not have to pick one now.',
              style: TextStyle(color: AppColors.hint, fontSize: 12)),
          const SizedBox(height: 8),
          // Availability is informational only — this is an explicit opt-out
          // of naming a slot, not a validation dead end.
          CheckboxListTile(
            value: _requestAnyTime,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Request any available time'),
            onChanged: (v) => setState(() {
              _requestAnyTime = v ?? false;
              if (_requestAnyTime) {
                _date = null;
                _time = null;
                _availableTimes = const [];
              }
            }),
          ),
          if (!_requestAnyTime) ...[
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(_date == null
                  ? 'Select a date (up to 90 days ahead)'
                  : '${_date!.year}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}'),
            ),
            const SizedBox(height: 14),
            const Text('Available time', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (_date == null)
              const Text('Select a date to see this doctor\'s published times.',
                  style: TextStyle(color: AppColors.hint))
            else if (_loadingTimes)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_availableTimes.isEmpty)
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text(
                    'No published times on this date — you can still send the '
                    'request and the doctor will propose one.',
                    style: TextStyle(color: AppColors.hint)),
                const SizedBox(height: 6),
                OutlinedButton(
                  onPressed: () => setState(() {
                    _requestAnyTime = true;
                    _date = null;
                    _time = null;
                    _availableTimes = const [];
                  }),
                  child: const Text('Request any available time instead'),
                ),
              ])
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableTimes
                    .map((t) => ChoiceChip(
                          label: Text(t),
                          selected: _time == t,
                          onSelected: (_) => setState(() => _time = t),
                        ))
                    .toList(),
              ),
          ],
          const SizedBox(height: 16),
          const Text('Symptoms *', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextField(
            controller: _symptoms,
            maxLines: 2,
            decoration: const InputDecoration(
                hintText: 'One per line or comma-separated, e.g. Lethargy, Reduced feed intake'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _mortality,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Mortality count'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _farmerNotes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Additional notes (optional)'),
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('More farm details (optional)',
                style: TextStyle(fontSize: 13, color: AppColors.hint)),
            children: [
              TextField(
                controller: _feedNotes,
                decoration: const InputDecoration(labelText: 'Feed notes'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _vaccineHistory,
                decoration: const InputDecoration(labelText: 'Vaccine history'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _biosecurityNotes,
                decoration: const InputDecoration(labelText: 'Biosecurity notes'),
              ),
              const SizedBox(height: 8),
            ],
          ),
          if (_submitError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_submitError!, style: const TextStyle(color: AppColors.error)),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _farms.isEmpty || _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_outlined),
              label: Text(_submitting ? 'Sending request…' : 'Request consultation'),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _labeled(String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          child,
        ],
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
