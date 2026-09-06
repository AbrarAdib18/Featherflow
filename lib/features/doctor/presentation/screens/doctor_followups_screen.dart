import 'package:flutter/material.dart';
import '../../data/models/doctor_models.dart';
import '../../data/services/doctor_session.dart';
import '../doctor_theme.dart';
import 'doctor_case_notes_screen.dart';

class DoctorFollowupsScreen extends StatelessWidget {
  const DoctorFollowupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DoctorSession.instance,
      builder: (context, _) {
        final all = DoctorSession.instance.cases.toList();

        final overdue = all
            .where((c) =>
                c.status == CaseStatus.followUp &&
                c.followUpDate != null &&
                c.followUpDate!.isBefore(DateTime.now()))
            .toList()
          ..sort((a, b) => a.followUpDate!.compareTo(b.followUpDate!));

        final upcoming = all
            .where((c) =>
                c.status == CaseStatus.followUp &&
                (c.followUpDate == null ||
                    c.followUpDate!.isAfter(DateTime.now())))
            .toList()
          ..sort((a, b) {
            if (a.followUpDate == null) return 1;
            if (b.followUpDate == null) return -1;
            return a.followUpDate!.compareTo(b.followUpDate!);
          });

        final total = overdue.length + upcoming.length;

        return Scaffold(
          backgroundColor: VetColors.bg,
          appBar: AppBar(
            backgroundColor: VetColors.appBar,
            foregroundColor: Colors.white,
            title: Row(
              children: [
                const Text(
                  'Follow-Ups',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                if (total > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$total',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
          body: total == 0
              ? const _EmptyState()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (overdue.isNotEmpty) ...[
                      _sectionHeader(
                        'Overdue',
                        overdue.length,
                        VetColors.emergency,
                        VetColors.emergencyLight,
                      ),
                      const SizedBox(height: 8),
                      ...overdue.map((c) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child:
                                _FollowUpCard(doctorCase: c, isOverdue: true),
                          )),
                      const SizedBox(height: 16),
                    ],
                    if (upcoming.isNotEmpty) ...[
                      _sectionHeader(
                        'Upcoming',
                        upcoming.length,
                        VetColors.followUpColor,
                        VetColors.followUpLight,
                      ),
                      const SizedBox(height: 8),
                      ...upcoming.map((c) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child:
                                _FollowUpCard(doctorCase: c, isOverdue: false),
                          )),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
        );
      },
    );
  }

  Widget _sectionHeader(String title, int count, Color color, Color bg) => Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

// ── Follow-Up Card ────────────────────────────────────────────────────────────

class _FollowUpCard extends StatelessWidget {
  final DoctorCase doctorCase;
  final bool isOverdue;
  const _FollowUpCard({required this.doctorCase, required this.isOverdue});

  String _formatDate(DateTime d) {
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
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _formatClock(DateTime d) {
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$hour:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  String _daysLabel(DateTime d) {
    final diff = d.difference(DateTime.now()).inDays;
    if (diff < 0) return '${-diff}d overdue';
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    return 'In $diff days';
  }

  (Color, Color, String) get _urgencyAttrs => switch (doctorCase.urgency) {
        CaseUrgency.routine => (
            VetColors.routineLight,
            VetColors.routine,
            'Routine'
          ),
        CaseUrgency.moderate => (
            VetColors.moderateLight,
            VetColors.moderate,
            'Moderate'
          ),
        CaseUrgency.urgent => (
            VetColors.urgentLight,
            VetColors.urgent,
            'Urgent'
          ),
        CaseUrgency.emergency => (
            VetColors.emergencyLight,
            VetColors.emergency,
            'Emergency'
          ),
      };

  @override
  Widget build(BuildContext context) {
    final c = doctorCase;
    final accentColor =
        isOverdue ? VetColors.emergency : VetColors.followUpColor;
    final (urgBg, urgFg, urgLabel) = _urgencyAttrs;

    return Container(
      decoration: vetCard(
        borderColor:
            isOverdue ? VetColors.emergency.withValues(alpha: 0.4) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(Icons.event_repeat, color: accentColor, size: 15),
                const SizedBox(width: 6),
                Text(
                  c.followUpDate != null
                      ? '${_formatDate(c.followUpDate!)} • ${_formatClock(c.followUpDate!)}'
                      : 'Date and time not set',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (c.followUpDate != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _daysLabel(c.followUpDate!),
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.farmName,
                            style: const TextStyle(
                              color: VetColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            c.farmerName,
                            style: const TextStyle(
                                color: VetColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: urgBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: urgFg.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        urgLabel,
                        style: TextStyle(
                            color: urgFg,
                            fontSize: 10,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Flock summary
                Wrap(
                  spacing: 8,
                  children: [
                    _chip(Icons.egg_outlined, '${c.flockSize} birds',
                        VetColors.textSecondary),
                    _chip(Icons.pets, c.breed, VetColors.textSecondary),
                    if (c.mortalityCount > 0)
                      _chip(Icons.warning_amber, '${c.mortalityCount} dead',
                          VetColors.red),
                  ],
                ),
                if (c.diagnosis != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: VetColors.surface2,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.biotech_outlined,
                            size: 13, color: VetColors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            c.diagnosis!,
                            style: const TextStyle(
                              color: VetColors.textSecondary,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _reschedule(context),
                        icon: const Icon(Icons.event_outlined, size: 14),
                        label: const Text('Reschedule'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: VetColors.followUpColor,
                          side: BorderSide(
                              color: VetColors.followUpColor
                                  .withValues(alpha: 0.5)),
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
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => CaseDetailScreen(caseId: c.id)),
                        ),
                        icon: const Icon(Icons.folder_open_outlined, size: 14),
                        label: const Text('Open Case'),
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ],
      );

  Future<void> _reschedule(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 3)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (date != null && context.mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: doctorCase.followUpDate == null
            ? const TimeOfDay(hour: 10, minute: 0)
            : TimeOfDay.fromDateTime(doctorCase.followUpDate!),
      );
      if (time == null) return;
      final scheduled =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
      DoctorSession.instance.setFollowUpDate(doctorCase.id, scheduled);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Follow-up rescheduled to ${_formatDate(scheduled)} at ${time.format(context)}.'),
            backgroundColor: VetColors.followUpColor,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_repeat,
            size: 52,
            color: VetColors.grey.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          const Text(
            'No follow-ups scheduled',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: VetColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Set follow-up dates from case notes to see them here.',
            style: TextStyle(fontSize: 13, color: VetColors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
