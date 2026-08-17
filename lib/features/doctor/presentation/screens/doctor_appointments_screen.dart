import 'package:flutter/material.dart';
import '../../data/models/doctor_models.dart';
import '../../data/services/doctor_session.dart';
import '../doctor_theme.dart';
import '../widgets/doctor_availability_dialog.dart';

class DoctorAppointmentsScreen extends StatefulWidget {
  const DoctorAppointmentsScreen({super.key});

  @override
  State<DoctorAppointmentsScreen> createState() =>
      _DoctorAppointmentsScreenState();
}

class _DoctorAppointmentsScreenState extends State<DoctorAppointmentsScreen> {
  AppointmentStatus? _filter;

  List<DoctorAppointment> get _filtered {
    final all = DoctorSession.instance.appointments;
    if (_filter == null) return all.toList();
    return all.where((a) => a.status == _filter).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DoctorSession.instance,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: VetColors.bg,
          appBar: AppBar(
            backgroundColor: VetColors.appBar,
            automaticallyImplyLeading: false,
            title: const Text(
              'Schedule',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Set consultation times',
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const DoctorConsultationHoursDialog(),
                ),
                icon: const Icon(Icons.edit_calendar_outlined,
                    color: Colors.white),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _AvailabilityToggle(
                  availability: DoctorSession.instance.profile.availability,
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              _FilterBar(
                selected: _filter,
                onChanged: (f) => setState(() => _filter = f),
              ),
              Expanded(
                child: _filtered.isEmpty
                    ? _EmptyState(filter: _filter)
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) =>
                            _AppointmentCard(appointment: _filtered[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Availability Toggle ───────────────────────────────────────────────────────

class _AvailabilityToggle extends StatelessWidget {
  final DoctorAvailability availability;
  const _AvailabilityToggle({required this.availability});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (availability) {
      DoctorAvailability.available => (const Color(0xFF69F0AE), 'Available'),
      DoctorAvailability.busy => (const Color(0xFFFFB74D), 'Busy'),
      DoctorAvailability.offline => (Colors.white38, 'Offline'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white38),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter Bar ────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final AppointmentStatus? selected;
  final ValueChanged<AppointmentStatus?> onChanged;
  const _FilterBar({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final session = DoctorSession.instance;

    int count(AppointmentStatus? s) => s == null
        ? session.appointments.length
        : session.appointments.where((a) => a.status == s).length;

    final filters = <(AppointmentStatus?, String, Color)>[
      (null, 'All', VetColors.primary),
      (AppointmentStatus.pending, 'Pending', VetColors.amber),
      (AppointmentStatus.accepted, 'Accepted', VetColors.available),
      (AppointmentStatus.completed, 'Completed', VetColors.secondary),
      (AppointmentStatus.rejected, 'Rejected', VetColors.red),
      (AppointmentStatus.noShow, 'No-Show', VetColors.emergency),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: VetColors.bg,
        border: Border(bottom: BorderSide(color: VetColors.divider)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: filters.map((f) {
            final (status, label, color) = f;
            final isSelected = selected == status;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onChanged(status),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? color : VetColors.cardBorder,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected ? color : VetColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color.withValues(alpha: 0.15)
                              : VetColors.surface2,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${count(status)}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isSelected ? color : VetColors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Appointment Card ──────────────────────────────────────────────────────────

class _AppointmentCard extends StatelessWidget {
  final DoctorAppointment appointment;
  const _AppointmentCard({required this.appointment});

  String _formatDateTime(DateTime dt) {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} · $h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final isUrgent = a.isUrgent;
    final isPending = a.status == AppointmentStatus.pending;

    return Container(
      decoration: vetCard(
        highlight: isUrgent,
        borderColor:
            isUrgent ? VetColors.emergency.withValues(alpha: 0.5) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isUrgent ? VetColors.emergencyLight : VetColors.surface2,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Text(
                  '#${a.id}',
                  style: TextStyle(
                    color: isUrgent
                        ? VetColors.emergency
                        : VetColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (isUrgent) ...[
                  const Icon(Icons.warning_amber_rounded,
                      color: VetColors.emergency, size: 14),
                  const SizedBox(width: 4),
                  const Text(
                    'URGENT',
                    style: TextStyle(
                      color: VetColors.emergency,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                _StatusChip(status: a.status),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor:
                          VetColors.secondary.withValues(alpha: 0.12),
                      child: Text(
                        a.farmerName.isNotEmpty ? a.farmerName[0] : 'F',
                        style: const TextStyle(
                          color: VetColors.secondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.farmerName,
                            style: const TextStyle(
                              color: VetColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            a.farmName,
                            style: const TextStyle(
                              color: VetColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            a.farmerPhone,
                            style: const TextStyle(
                              color: VetColors.grey,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '৳${a.fee.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: VetColors.secondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: VetColors.divider),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.access_time,
                        size: 14, color: VetColors.grey),
                    const SizedBox(width: 5),
                    Text(
                      _formatDateTime(a.scheduledAt),
                      style: const TextStyle(
                          color: VetColors.textSecondary, fontSize: 12),
                    ),
                    const Spacer(),
                    _ModeBadge(mode: a.mode),
                  ],
                ),
                if (a.notes != null && a.notes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: VetColors.surface2,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.notes,
                            size: 14, color: VetColors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            a.notes!,
                            style: const TextStyle(
                              color: VetColors.textSecondary,
                              fontSize: 12,
                              height: 1.4,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (isPending) ...[
                  const SizedBox(height: 12),
                  _ActionButtons(appointment: a),
                ] else if (a.status == AppointmentStatus.accepted) ...[
                  const SizedBox(height: 12),
                  _AcceptedActions(appointment: a),
                ] else if (a.status == AppointmentStatus.completed) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _ActionButtons(appointment: a)
                          ._showPrescriptionDialog(context, a),
                      icon: const Icon(Icons.medication_outlined),
                      label: const Text('Issue prescription & advice'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final AppointmentStatus status;
  const _StatusChip({required this.status});

  (Color bg, Color fg, String label) get _attrs => switch (status) {
        AppointmentStatus.pending => (
            VetColors.amberLight,
            VetColors.amber,
            'Pending'
          ),
        AppointmentStatus.accepted => (
            VetColors.availableLight,
            VetColors.available,
            'Accepted'
          ),
        AppointmentStatus.completed => (
            VetColors.closedLight,
            VetColors.closed,
            'Completed'
          ),
        AppointmentStatus.rejected => (
            VetColors.redLight,
            VetColors.red,
            'Rejected'
          ),
        AppointmentStatus.rescheduled => (
            VetColors.moderateLight,
            VetColors.moderate,
            'Rescheduled'
          ),
        AppointmentStatus.noShow => (
            VetColors.redLight,
            VetColors.red,
            'No-Show'
          ),
      };

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = _attrs;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  final AppointmentMode mode;
  const _ModeBadge({required this.mode});

  @override
  Widget build(BuildContext context) {
    final (icon, color, bg, label) = switch (mode) {
      AppointmentMode.online => (
          Icons.videocam_outlined,
          VetColors.online,
          VetColors.onlineLight,
          'Online'
        ),
      AppointmentMode.inPerson => (
          Icons.location_on_outlined,
          VetColors.inPerson,
          VetColors.inPersonLight,
          'In-Person'
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final DoctorAppointment appointment;
  const _ActionButtons({required this.appointment});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showRejectDialog(context),
            icon: const Icon(Icons.close, size: 15),
            label: const Text('Reject'),
            style: OutlinedButton.styleFrom(
              foregroundColor: VetColors.red,
              side: BorderSide(color: VetColors.red.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showRescheduleDialog(context),
            icon: const Icon(Icons.event_outlined, size: 15),
            label: const Text('Reschedule'),
            style: OutlinedButton.styleFrom(
              foregroundColor: VetColors.moderate,
              side:
                  BorderSide(color: VetColors.moderate.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: () {
              DoctorSession.instance.updateAppointmentStatus(
                appointment.id,
                AppointmentStatus.accepted,
              );
              _snack(context, 'Appointment accepted!', VetColors.available);
            },
            icon: const Icon(Icons.check, size: 15),
            label: const Text('Accept'),
            style: ElevatedButton.styleFrom(
              backgroundColor: VetColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  void _showRescheduleDialog(BuildContext context) {
    var date = appointment.scheduledAt.add(const Duration(days: 1));
    var time = TimeOfDay.fromDateTime(appointment.scheduledAt);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
                title: const Text('Reschedule Appointment'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                      'Propose a new time. The farmer must accept it before the consultation is confirmed.'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                      onPressed: () async {
                        final value = await showDatePicker(
                            context: ctx,
                            initialDate: date,
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 90)));
                        if (value != null) setLocal(() => date = value);
                      },
                      icon: const Icon(Icons.calendar_today),
                      label: Text('${date.day}/${date.month}/${date.year}')),
                  OutlinedButton.icon(
                      onPressed: () async {
                        final value = await showTimePicker(
                            context: ctx, initialTime: time);
                        if (value != null) setLocal(() => time = value);
                      },
                      icon: const Icon(Icons.schedule),
                      label: Text(time.format(ctx))),
                ]),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final scheduled = DateTime(date.year, date.month,
                          date.day, time.hour, time.minute);
                      try {
                        await DoctorSession.instance
                            .rescheduleAppointment(appointment.id, scheduled);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          _snack(context, 'Reschedule proposal sent.',
                              VetColors.moderate);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          _snack(context, e.toString(), VetColors.red);
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: VetColors.primary),
                    child: const Text('Confirm',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              )),
    );
  }

  void _snack(BuildContext context, String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _showRejectDialog(BuildContext context) async {
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject consultation'),
        content: TextField(
          controller: reason,
          maxLines: 3,
          decoration: const InputDecoration(
              labelText: 'Reason (optional)', alignLabelWithHint: true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep request')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Reject')),
        ],
      ),
    );
    if (accepted == true) {
      try {
        await DoctorSession.instance
            .rejectAppointment(appointment.id, reason.text.trim());
        if (context.mounted) {
          _snack(context, 'Appointment rejected.', VetColors.red);
        }
      } catch (_) {
        if (context.mounted) {
          _snack(context, 'Could not reject appointment.', VetColors.red);
        }
      }
    }
    reason.dispose();
  }

  Future<void> _showPrescriptionDialog(
      BuildContext context, DoctorAppointment appointment) async {
    final medicine = TextEditingController();
    final dosage = TextEditingController();
    final duration = TextEditingController();
    final instructions = TextEditingController();
    final advice = TextEditingController();
    final followUp = TextEditingController();
    DateTime? followUpDate;
    TimeOfDay followUpTime = const TimeOfDay(hour: 10, minute: 0);
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Prescription and case advice'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: medicine,
                    decoration: const InputDecoration(labelText: 'Medicine *')),
                TextField(
                    controller: dosage,
                    decoration: const InputDecoration(labelText: 'Dosage *')),
                TextField(
                    controller: duration,
                    decoration: const InputDecoration(labelText: 'Duration *')),
                TextField(
                    controller: instructions,
                    decoration: const InputDecoration(
                        labelText: 'Medicine instructions')),
                TextField(
                    controller: advice,
                    maxLines: 3,
                    decoration:
                        const InputDecoration(labelText: 'Case advice *')),
                TextField(
                    controller: followUp,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Follow-up instructions')),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final selected = await showDatePicker(
                      context: dialogContext,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (selected != null) {
                      setLocal(() => followUpDate = selected);
                    }
                  },
                  icon: const Icon(Icons.event),
                  label: Text(followUpDate == null
                      ? 'Optional follow-up date'
                      : '${followUpDate!.day}/${followUpDate!.month}/${followUpDate!.year}'),
                ),
                if (followUpDate != null)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final selected = await showTimePicker(
                        context: dialogContext,
                        initialTime: followUpTime,
                      );
                      if (selected != null) {
                        setLocal(() => followUpTime = selected);
                      }
                    },
                    icon: const Icon(Icons.schedule),
                    label:
                        Text('Follow-up time: ${followUpTime.format(context)}'),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (medicine.text.trim().isEmpty ||
                    dosage.text.trim().isEmpty ||
                    duration.text.trim().isEmpty ||
                    advice.text.trim().isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                          content: Text('Complete all required fields.')));
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save and email PDF'),
            ),
          ],
        ),
      ),
    );
    if (submitted == true) {
      try {
        await DoctorSession.instance.issuePrescription(
          consultationId: appointment.id,
          medicine: medicine.text.trim(),
          dosage: dosage.text.trim(),
          duration: duration.text.trim(),
          instructions: instructions.text.trim(),
          caseAdvice: advice.text.trim(),
          followUpInstructions: followUp.text.trim(),
          followUpDate: followUpDate == null
              ? null
              : DateTime(
                  followUpDate!.year,
                  followUpDate!.month,
                  followUpDate!.day,
                  followUpTime.hour,
                  followUpTime.minute,
                ),
        );
        if (context.mounted) {
          _snack(context, 'Prescription saved and queued for email.',
              VetColors.available);
        }
      } catch (error) {
        if (context.mounted) {
          _snack(context, error.toString(), VetColors.red);
        }
      }
    }
    for (final controller in [
      medicine,
      dosage,
      duration,
      instructions,
      advice,
      followUp
    ]) {
      controller.dispose();
    }
  }
}

class _AcceptedActions extends StatelessWidget {
  final DoctorAppointment appointment;
  const _AcceptedActions({required this.appointment});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              DoctorSession.instance.updateAppointmentStatus(
                appointment.id,
                AppointmentStatus.noShow,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Marked as no-show.'),
                  backgroundColor: VetColors.red,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              );
            },
            icon: const Icon(Icons.person_off_outlined, size: 15),
            label: const Text('No-Show'),
            style: OutlinedButton.styleFrom(
              foregroundColor: VetColors.red,
              side: BorderSide(color: VetColors.red.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: () {
              DoctorSession.instance.updateAppointmentStatus(
                appointment.id,
                AppointmentStatus.completed,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Consultation marked as complete.'),
                  backgroundColor: VetColors.available,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              );
            },
            icon: const Icon(Icons.check_circle_outline, size: 15),
            label: const Text('Mark Complete'),
            style: ElevatedButton.styleFrom(
              backgroundColor: VetColors.available,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final AppointmentStatus? filter;
  const _EmptyState({required this.filter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 52,
            color: VetColors.grey.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            filter == null
                ? 'No appointments yet'
                : 'No ${_label(filter!)} appointments',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: VetColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'New bookings from farmers will appear here.',
            style: TextStyle(fontSize: 13, color: VetColors.grey),
          ),
        ],
      ),
    );
  }

  String _label(AppointmentStatus s) => switch (s) {
        AppointmentStatus.pending => 'pending',
        AppointmentStatus.accepted => 'accepted',
        AppointmentStatus.completed => 'completed',
        AppointmentStatus.rejected => 'rejected',
        AppointmentStatus.rescheduled => 'rescheduled',
        AppointmentStatus.noShow => 'no-show',
      };
}
