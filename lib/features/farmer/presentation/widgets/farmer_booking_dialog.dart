import 'package:flutter/material.dart';

import 'package:featherflow/core/theme/theme.dart';
import '../../data/vet_discovery_service.dart';

class FarmerBookingDialog extends StatefulWidget {
  const FarmerBookingDialog({super.key, required this.vet, this.preferredMode});
  final Map<String, dynamic> vet;
  final String? preferredMode;

  @override
  State<FarmerBookingDialog> createState() => _FarmerBookingDialogState();
}

class _FarmerBookingDialogState extends State<FarmerBookingDialog> {
  final _formKey = GlobalKey<FormState>();
  final _symptoms = TextEditingController();
  final _notes = TextEditingController();
  final _mortality = TextEditingController(text: '0');
  final _birdAge = TextEditingController();
  final _breed = TextEditingController();
  final _flockCount = TextEditingController();
  final _feedNotes = TextEditingController();
  final _vaccineHistory = TextEditingController();
  final _biosecurityNotes = TextEditingController();
  Map<String, dynamic>? _options;
  String? _farmId, _flockId, _selectedTime;
  late String _consultationMode;
  String _urgency = 'routine';
  DateTime _date = DateTime.now();
  bool _loading = true, _loadingSlots = false, _submitting = false;
  String? _error;

  List<Map<String, dynamic>> get _farms =>
      List<Map<String, dynamic>>.from((_options?['farms'] as List? ?? [])
          .map((x) => Map<String, dynamic>.from(x as Map)));
  Map<String, dynamic>? get _farm {
    for (final farm in _farms) {
      if (farm['id'] == _farmId) return farm;
    }
    return null;
  }

  List<Map<String, dynamic>> get _flocks =>
      List<Map<String, dynamic>>.from((_farm?['flocks'] as List? ?? [])
          .map((x) => Map<String, dynamic>.from(x as Map)));
  List<String> get _times =>
      List<String>.from(_options?['available_times'] as List? ?? []);

  @override
  void initState() {
    super.initState();
    _consultationMode = widget.preferredMode ??
        (widget.vet['mode'] == 'offline' ? 'offline' : 'online');
    _loadBase();
  }

  @override
  void dispose() {
    _symptoms.dispose();
    _notes.dispose();
    _mortality.dispose();
    _birdAge.dispose();
    _breed.dispose();
    _flockCount.dispose();
    _feedNotes.dispose();
    _vaccineHistory.dispose();
    _biosecurityNotes.dispose();
    super.dispose();
  }

  Future<void> _loadBase() async {
    try {
      final data =
          await VetDiscoveryService.bookingOptions(widget.vet['id'].toString());
      if (!mounted) return;
      setState(() {
        _options = data;
        _farmId = _farms.isEmpty ? null : _farms.first['id']?.toString();
        _flockId = _flocks.isEmpty ? null : _flocks.first['id']?.toString();
        _loading = false;
        _error = null;
      });
      await _loadSlots();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _loadSlots() async {
    setState(() {
      _loadingSlots = true;
      _selectedTime = null;
    });
    try {
      final data = await VetDiscoveryService.bookingOptions(
          widget.vet['id'].toString(),
          date: _date,
          mode: _consultationMode);
      if (mounted) {
        setState(() {
          _options = {...?_options, ...data};
          _loadingSlots = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingSlots = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
        context: context,
        initialDate: _date,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 90)));
    if (value != null) {
      setState(() => _date = value);
      await _loadSlots();
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() ||
        _selectedTime == null ||
        _farmId == null) {
      if (_selectedTime == null) {
        setState(() => _error = 'Choose one of the doctor’s available times.');
      }
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await VetDiscoveryService.book({
        'doctor_id': widget.vet['id'],
        'farm_id': _farmId,
        'flock_id': _flockId,
        'mode': _consultationMode,
        'urgency': _urgency,
        'appointment_date': VetDiscoveryService.formatDate(_date),
        'appointment_time': _selectedTime,
        'symptoms': _symptoms.text
            .split(',')
            .map((x) => x.trim())
            .where((x) => x.isNotEmpty)
            .toList(),
        'farmer_notes': _notes.text.trim(),
        'mortality_count': int.tryParse(_mortality.text) ?? 0,
        if (_flockId == null) 'bird_age_weeks': int.tryParse(_birdAge.text),
        if (_flockId == null) 'breed': _breed.text.trim(),
        if (_flockId == null) 'flock_count': int.tryParse(_flockCount.text),
        'feed_notes': _feedNotes.text.trim(),
        'vaccine_history': _vaccineHistory.text.trim(),
        'biosecurity_notes': _biosecurityNotes.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _submitting = false;
        });
        await _loadSlots();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
          child: _loading
              ? const Center(
                  child: Padding(
                      padding: EdgeInsets.all(48),
                      child: CircularProgressIndicator()))
              : _error != null && _options == null
                  ? _failure()
                  : Column(children: [
                      Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 8, 8),
                          child: Row(children: [
                            Expanded(
                                child: Text('Book ${widget.vet['name']}',
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primary))),
                            IconButton(
                                onPressed: _submitting
                                    ? null
                                    : () => Navigator.pop(context),
                                icon: const Icon(Icons.close)),
                          ])),
                      Expanded(
                          child: Form(
                              key: _formKey,
                              child: SingleChildScrollView(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 8, 20, 20),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _section('Farm and flock'),
                                        DropdownButtonFormField<String>(
                                            initialValue: _farmId,
                                            isExpanded: true,
                                            decoration: const InputDecoration(
                                                labelText: 'Farm'),
                                            items: _farms
                                                .map((x) => DropdownMenuItem(
                                                    value: x['id'].toString(),
                                                    child: Text(
                                                        x['name'].toString())))
                                                .toList(),
                                            validator: (x) => x == null
                                                ? 'An active farm is required'
                                                : null,
                                            onChanged: (x) => setState(() {
                                                  _farmId = x;
                                                  _flockId = _flocks.isEmpty
                                                      ? null
                                                      : _flocks.first['id']
                                                          ?.toString();
                                                })),
                                        const SizedBox(height: 12),
                                        DropdownButtonFormField<String?>(
                                            initialValue: _flockId,
                                            isExpanded: true,
                                            decoration: const InputDecoration(
                                                labelText: 'Flock (optional)'),
                                            items: [
                                              const DropdownMenuItem<String?>(
                                                  value: null,
                                                  child: Text(
                                                      'General farm consultation')),
                                              ..._flocks.map((x) =>
                                                  DropdownMenuItem(
                                                      value: x['id'].toString(),
                                                      child: Text(
                                                          '${x['name']} • ${x['breed']} • ${x['count']} birds')))
                                            ],
                                            onChanged: (x) =>
                                                setState(() => _flockId = x)),
                                        if (_flockId == null) ...[
                                          const SizedBox(height: 12),
                                          LayoutBuilder(
                                              builder: (context, box) {
                                            final fields = [
                                              TextFormField(
                                                  controller: _breed,
                                                  decoration:
                                                      const InputDecoration(
                                                          labelText: 'Breed'),
                                                  validator: _required),
                                              TextFormField(
                                                  controller: _birdAge,
                                                  keyboardType: TextInputType
                                                      .number,
                                                  decoration:
                                                      const InputDecoration(
                                                          labelText:
                                                              'Bird age (weeks)'),
                                                  validator: _positiveOrZero),
                                              TextFormField(
                                                  controller: _flockCount,
                                                  keyboardType: TextInputType
                                                      .number,
                                                  decoration:
                                                      const InputDecoration(
                                                          labelText:
                                                              'Flock count'),
                                                  validator: _positive),
                                            ];
                                            if (box.maxWidth < 520) {
                                              return Column(children: [
                                                fields[0],
                                                const SizedBox(height: 12),
                                                fields[1],
                                                const SizedBox(height: 12),
                                                fields[2]
                                              ]);
                                            }
                                            return Row(children: [
                                              Expanded(child: fields[0]),
                                              const SizedBox(width: 8),
                                              Expanded(child: fields[1]),
                                              const SizedBox(width: 8),
                                              Expanded(child: fields[2])
                                            ]);
                                          }),
                                        ],
                                        const SizedBox(height: 20),
                                        _section('Consultation schedule'),
                                        LayoutBuilder(builder: (context, box) {
                                          final children = [
                                            _modeField(),
                                            _urgencyField()
                                          ];
                                          return box.maxWidth < 480
                                              ? Column(children: [
                                                  children[0],
                                                  const SizedBox(height: 12),
                                                  children[1]
                                                ])
                                              : Row(children: [
                                                  Expanded(child: children[0]),
                                                  const SizedBox(width: 12),
                                                  Expanded(child: children[1])
                                                ]);
                                        }),
                                        const SizedBox(height: 12),
                                        OutlinedButton.icon(
                                            onPressed: _pickDate,
                                            icon: const Icon(
                                                Icons.calendar_today_outlined),
                                            label: Text(
                                                '${_date.day}/${_date.month}/${_date.year}')),
                                        const SizedBox(height: 12),
                                        if (_loadingSlots)
                                          const Center(
                                              child:
                                                  CircularProgressIndicator())
                                        else if (_times.isEmpty)
                                          const Padding(
                                              padding: EdgeInsets.all(16),
                                              child: Text(
                                                  'No available times on this date. Select another date or mode.',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                      color: Colors.orange)))
                                        else
                                          Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: _times
                                                  .map((x) => ChoiceChip(
                                                      label: Text(x),
                                                      selected:
                                                          _selectedTime == x,
                                                      onSelected: (_) =>
                                                          setState(() =>
                                                              _selectedTime =
                                                                  x)))
                                                  .toList()),
                                        const SizedBox(height: 20),
                                        _section('Poultry symptoms'),
                                        TextFormField(
                                            controller: _symptoms,
                                            minLines: 2,
                                            maxLines: 4,
                                            decoration: const InputDecoration(
                                                labelText: 'Symptoms',
                                                hintText:
                                                    'Sneezing, weak appetite, reduced activity'),
                                            validator: (x) => x == null ||
                                                    x
                                                        .split(',')
                                                        .where((v) =>
                                                            v.trim().isNotEmpty)
                                                        .isEmpty
                                                ? 'Enter at least one symptom'
                                                : null),
                                        const SizedBox(height: 12),
                                        TextFormField(
                                            controller: _feedNotes,
                                            minLines: 1,
                                            maxLines: 3,
                                            decoration: const InputDecoration(
                                                labelText:
                                                    'Feed notes (optional)',
                                                hintText:
                                                    'Feed type, recent change, reduced intake')),
                                        const SizedBox(height: 12),
                                        TextFormField(
                                            controller: _vaccineHistory,
                                            minLines: 1,
                                            maxLines: 3,
                                            decoration: const InputDecoration(
                                                labelText:
                                                    'Vaccine history (optional)')),
                                        const SizedBox(height: 12),
                                        TextFormField(
                                            controller: _biosecurityNotes,
                                            minLines: 1,
                                            maxLines: 3,
                                            decoration: const InputDecoration(
                                                labelText:
                                                    'Biosecurity notes (optional)',
                                                hintText:
                                                    'Recent visitors, new birds, sanitation concerns')),
                                        const SizedBox(height: 12),
                                        TextFormField(
                                            controller: _mortality,
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(
                                                labelText: 'Mortality count'),
                                            validator: (x) => (int.tryParse(
                                                            x ?? '') ??
                                                        -1) <
                                                    0
                                                ? 'Enter zero or a positive number'
                                                : null),
                                        const SizedBox(height: 12),
                                        TextFormField(
                                            controller: _notes,
                                            minLines: 2,
                                            maxLines: 4,
                                            decoration: const InputDecoration(
                                                labelText:
                                                    'Additional notes (optional)')),
                                        if (_error != null)
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 12),
                                              child: Text(_error!,
                                                  style: const TextStyle(
                                                      color: Colors.red))),
                                        const SizedBox(height: 16),
                                        Text(
                                            'Consultation fee: ৳${widget.vet['fee']}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800)),
                                      ])))),
                      SafeArea(
                          top: false,
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(children: [
                                Expanded(
                                    child: OutlinedButton(
                                        onPressed: _submitting
                                            ? null
                                            : () => Navigator.pop(context),
                                        child: const Text('Cancel'))),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: ElevatedButton(
                                        onPressed: _submitting ? null : _submit,
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.primary,
                                            foregroundColor: Colors.white),
                                        child: _submitting
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white))
                                            : const Text('Send request'))),
                              ]))),
                    ]),
        ),
      );

  Widget _failure() => Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: _loadBase, child: const Text('Retry'))
      ]));
  Widget _section(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text,
          style: const TextStyle(
              fontWeight: FontWeight.w800, color: AppColors.primary)));
  Widget _modeField() => DropdownButtonFormField<String>(
      initialValue: _consultationMode,
      decoration: const InputDecoration(labelText: 'Mode'),
      items: ['online', 'offline']
          .where((x) => widget.vet['mode'] == 'both' || widget.vet['mode'] == x)
          .map((x) => DropdownMenuItem(
              value: x, child: Text(x == 'online' ? 'Online' : 'In-person')))
          .toList(),
      onChanged: (x) async {
        if (x != null) {
          setState(() => _consultationMode = x);
          await _loadSlots();
        }
      });
  Widget _urgencyField() => DropdownButtonFormField<String>(
      initialValue: _urgency,
      decoration: const InputDecoration(labelText: 'Urgency'),
      items: ['routine', 'moderate', 'urgent', 'emergency']
          .map((x) => DropdownMenuItem(value: x, child: Text(x)))
          .toList(),
      onChanged: (x) => setState(() => _urgency = x!));

  static String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
  static String? _positiveOrZero(String? value) =>
      (int.tryParse(value ?? '') ?? -1) < 0 ? 'Enter 0 or more' : null;
  static String? _positive(String? value) =>
      (int.tryParse(value ?? '') ?? 0) < 1 ? 'Enter 1 or more' : null;
}
