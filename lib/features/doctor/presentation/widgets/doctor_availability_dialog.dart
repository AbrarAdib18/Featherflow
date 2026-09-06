import 'package:flutter/material.dart';

import '../../data/services/doctor_api_service.dart';
import '../doctor_theme.dart';

class DoctorConsultationHoursDialog extends StatefulWidget {
  const DoctorConsultationHoursDialog({super.key});

  @override
  State<DoctorConsultationHoursDialog> createState() =>
      _DoctorConsultationHoursDialogState();
}

class _DoctorConsultationHoursDialogState
    extends State<DoctorConsultationHoursDialog> {
  static const _days = <String>[
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];

  List<Map<String, dynamic>> _slots = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _weekday = DateTime.now().weekday - 1;
  String _consultationMode = 'online';
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 17, minute: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await DoctorApiService.get('availability');
      if (!mounted) return;
      setState(() {
        _slots = List<Map<String, dynamic>>.from(
          (data['slots'] as List? ?? const [])
              .map((value) => Map<String, dynamic>.from(value as Map)),
        );
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() { _loading = false; _error = error.toString(); });
    }
  }

  String _apiTime(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  int _minutes(TimeOfDay value) => value.hour * 60 + value.minute;

  Future<void> _add() async {
    if (_minutes(_end) <= _minutes(_start)) {
      setState(() => _error = 'End time must be after start time.');
      return;
    }
    if (_minutes(_end) - _minutes(_start) < 30) {
      setState(() => _error = 'Availability must include at least one 30-minute consultation.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await DoctorApiService.post('availability', {
        'weekday': _weekday,
        'start_time': _apiTime(_start),
        'end_time': _apiTime(_end),
        'mode': _consultationMode,
      });
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(Map<String, dynamic> slot) async {
    setState(() { _saving = true; _error = null; });
    try {
      await DoctorApiService.delete('availability', {'id': slot['id']});
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickStart() async {
    final value = await showTimePicker(context: context, initialTime: _start);
    if (value != null && mounted) setState(() => _start = value);
  }

  Future<void> _pickEnd() async {
    final value = await showTimePicker(context: context, initialTime: _end);
    if (value != null && mounted) setState(() => _end = value);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: (media.size.height - media.viewInsets.bottom - 48) < 240
              ? 240
              : media.size.height - media.viewInsets.bottom - 48,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
            child: Row(children: [
              const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Consultation availability', style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800,
                    color: VetColors.primary,
                  )),
                  SizedBox(height: 3),
                  Text('Farmers can request only these weekly time slots.',
                    style: TextStyle(fontSize: 12, color: VetColors.textSecondary)),
                ],
              )),
              IconButton(onPressed: _saving ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close)),
            ]),
          ),
          const Divider(height: 1),
          Flexible(child: _loading
              ? const Center(child: Padding(padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator()))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    LayoutBuilder(builder: (context, box) {
                      final day = DropdownButtonFormField<int>(
                        initialValue: _weekday,
                        decoration: const InputDecoration(labelText: 'Day'),
                        items: List.generate(_days.length, (i) =>
                          DropdownMenuItem(value: i, child: Text(_days[i]))),
                        onChanged: _saving ? null : (value) =>
                          setState(() => _weekday = value ?? _weekday),
                      );
                      final mode = DropdownButtonFormField<String>(
                        initialValue: _consultationMode,
                        decoration: const InputDecoration(labelText: 'Consultation mode'),
                        items: const [
                          DropdownMenuItem(value: 'online', child: Text('Online')),
                          DropdownMenuItem(value: 'offline', child: Text('In-person')),
                        ],
                        onChanged: _saving ? null : (value) =>
                          setState(() => _consultationMode = value ?? _consultationMode),
                      );
                      return box.maxWidth < 480
                          ? Column(children: [day, const SizedBox(height: 12), mode])
                          : Row(children: [Expanded(child: day), const SizedBox(width: 12),
                              Expanded(child: mode)]);
                    }),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: OutlinedButton.icon(onPressed: _saving ? null : _pickStart,
                        icon: const Icon(Icons.schedule),
                        label: Text('From ${_start.format(context)}'))),
                      const SizedBox(width: 12),
                      Expanded(child: OutlinedButton.icon(onPressed: _saving ? null : _pickEnd,
                        icon: const Icon(Icons.schedule),
                        label: Text('To ${_end.format(context)}'))),
                    ]),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _saving ? null : _add,
                      icon: _saving
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.add),
                      label: const Text('Publish time'),
                      style: FilledButton.styleFrom(backgroundColor: VetColors.primary),
                    ),
                    if (_error != null) Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!, style: const TextStyle(color: VetColors.red)),
                    ),
                    const SizedBox(height: 22),
                    const Text('Published weekly times', style: TextStyle(
                      fontWeight: FontWeight.w800, color: VetColors.primary)),
                    const SizedBox(height: 8),
                    if (_slots.isEmpty)
                      const Padding(padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('No times published yet. Add a time above so farmers can book.',
                          textAlign: TextAlign.center, style: TextStyle(color: VetColors.textSecondary)))
                    else
                      ..._slots.map((slot) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(slot['mode'] == 'online'
                              ? Icons.videocam_outlined : Icons.location_on_outlined,
                            color: VetColors.primary),
                          title: Text(_days[(slot['weekday'] as num).toInt()],
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${slot['start_time']} - ${slot['end_time']}  |  '
                            '${slot['mode'] == 'online' ? 'Online' : 'In-person'}'),
                          trailing: IconButton(
                            tooltip: 'Remove time',
                            onPressed: _saving ? null : () => _remove(slot),
                            icon: const Icon(Icons.delete_outline, color: VetColors.red),
                          ),
                        ),
                      )),
                  ]),
                )),
        ]),
      ),
    );
  }
}
