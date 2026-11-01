import 'package:flutter/material.dart';
import '../../data/models/doctor_models.dart';
import '../../data/services/doctor_session.dart';
import '../doctor_theme.dart';
import '../widgets/doctor_availability_dialog.dart';
import 'doctor_case_notes_screen.dart' show CaseDetailScreen;

// The Schedule page holds only incoming consultation requests and upcoming
// appointments (DOCTOR_SCHEDULE_PAGE_AUDIT.md). Case work — clinical notes,
// Close case, Mark as Complete, prescriptions — lives on the Case page.

class DoctorAppointmentsScreen extends StatefulWidget {
  const DoctorAppointmentsScreen({super.key});

  @override
  State<DoctorAppointmentsScreen> createState() =>
      _DoctorAppointmentsScreenState();
}

class _DoctorAppointmentsScreenState extends State<DoctorAppointmentsScreen>
    with WidgetsBindingObserver {

  // Refreshes on screen entry and on app foreground return, in addition to
  // the session's own triggers (login, every action, and every newly arrived
  // notification). See DOCTOR_CONSULTATION_QUEUE_FIX.md.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // After the first frame: this screen is also built inside the dashboard's
    // IndexedStack, and refresh() notifies listeners, which must not happen
    // while the parent ListenableBuilder is mid-build.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => DoctorSession.instance.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) DoctorSession.instance.refresh();
  }

  List<DoctorAppointment> _section(ScheduleSection section) =>
      DoctorSession.instance.appointments
          .where((a) => a.scheduleSection == section)
          .toList()
        ..sort((a, b) => a.sortKey.compareTo(b.sortKey));

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
              if (DoctorSession.instance.error != null)
                _RefreshErrorBanner(
                  message: DoctorSession.instance.error!,
                  hasData: DoctorSession.instance.appointmentsLoaded,
                ),
              Expanded(
                // Spinner until the first real load succeeds or fails — never
                // a misleading "no consultations" before data has arrived.
                child: !DoctorSession.instance.appointmentsLoaded &&
                        DoctorSession.instance.error == null
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: DoctorSession.instance.refresh,
                        child: _scheduleList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _scheduleList() {
    final requests = _section(ScheduleSection.requests);
    final upcoming = _section(ScheduleSection.upcoming);
    return ListView(
      key: const Key('doctorAppointmentsList'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader(
          key: const Key('scheduleRequestsSection'),
          icon: Icons.inbox_outlined,
          title: 'Consultation Requests',
          count: requests.length,
        ),
        if (requests.isEmpty)
          const _SectionEmpty(
            key: Key('scheduleRequestsEmpty'),
            icon: Icons.inbox_outlined,
            title: 'No pending consultation requests',
            body: 'New bookings from farmers will appear here.',
          ),
        for (final a in requests) ...[
          _AppointmentCard(appointment: a),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 14),
        _SectionHeader(
          key: const Key('scheduleUpcomingSection'),
          icon: Icons.event_available_outlined,
          title: 'Upcoming Schedule',
          count: upcoming.length,
        ),
        if (upcoming.isEmpty)
          const _SectionEmpty(
            key: Key('scheduleUpcomingEmpty'),
            icon: Icons.calendar_today_outlined,
            title: 'No upcoming schedules',
            body: 'Accepted consultations appear here until they are '
                'completed from their Case page.',
          ),
        for (final a in upcoming) ...[
          _AppointmentCard(appointment: a),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {super.key, required this.icon, required this.title, required this.count});
  final IconData icon;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(icon, size: 18, color: VetColors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    color: VetColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: VetColors.surface2,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: const TextStyle(
                    color: VetColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}

class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty(
      {super.key, required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        decoration: vetCard(),
        child: Column(children: [
          Icon(icon, size: 36, color: VetColors.grey),
          const SizedBox(height: 8),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: VetColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(body,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: VetColors.textSecondary, fontSize: 12)),
        ]),
      );
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
                        color: VetColors.available,
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
                    Flexible(
                      child: Text(
                        a.scheduledAt != null
                            ? _formatDateTime(a.scheduledAt!)
                            : a.status == AppointmentStatus.pending
                                ? 'Any time — propose a slot when accepting'
                                : 'No time was set',
                        key: const Key('appointmentSlotText'),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: VetColors.textSecondary, fontSize: 12),
                      ),
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
                ] else if (a.status == AppointmentStatus.rescheduled) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Waiting for the farmer to accept your proposed time.',
                    style: TextStyle(
                        color: VetColors.textSecondary, fontSize: 12),
                  ),
                ] else if (a.scheduleSection == ScheduleSection.upcoming) ...[
                  const SizedBox(height: 12),
                  _UpcomingActions(appointment: a),
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
            VetColors.amberText,
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
            VetColors.followUpLight,
            VetColors.followUpColor,
            'Time proposed'
          ),
        AppointmentStatus.inProgress => (
            VetColors.busyLight,
            VetColors.busy,
            'In Progress'
          ),
        AppointmentStatus.cancelled => (
            VetColors.surface2,
            VetColors.textSecondary,
            'Cancelled'
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

class _ActionButtons extends StatefulWidget {
  final DoctorAppointment appointment;
  const _ActionButtons({required this.appointment});

  @override
  State<_ActionButtons> createState() => _ActionButtonsState();
}

class _ActionButtonsState extends State<_ActionButtons> {
  bool _busy = false;

  DoctorAppointment get appointment => widget.appointment;

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Reports the server's actual answer; this used to announce success
    // before the request had even returned.
    final error = await DoctorSession.instance
        .updateAppointmentStatus(appointment.id, AppointmentStatus.accepted);
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    _snack(context, error ?? 'Appointment accepted!',
        error == null ? VetColors.available : VetColors.red);
  }

  @override
  Widget build(BuildContext context) {
    final reject = OutlinedButton.icon(
      onPressed: _busy ? null : () => _showRejectDialog(context),
      icon: const Icon(Icons.close, size: 15),
      label: const Text('Reject', maxLines: 1, softWrap: false),
      style: OutlinedButton.styleFrom(
        foregroundColor: VetColors.red,
        side: BorderSide(color: VetColors.red.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
    final reschedule = OutlinedButton.icon(
      onPressed: _busy ? null : () => _showRescheduleDialog(context),
      icon: const Icon(Icons.event_outlined, size: 15),
      label: const Text('Reschedule', maxLines: 1, softWrap: false),
      style: OutlinedButton.styleFrom(
        foregroundColor: VetColors.busy,
        side: BorderSide(color: VetColors.busy.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
    final accept = ElevatedButton.icon(
      onPressed: _busy ? null : _accept,
      icon: _busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.check, size: 15),
      label: const Text('Accept', maxLines: 1, softWrap: false),
      style: ElevatedButton.styleFrom(
        backgroundColor: VetColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
    return LayoutBuilder(builder: (context, constraints) {
      // Under ~400px the three buttons don't fit on one line with readable
      // labels ("Reschedul/e" wrapped): Accept goes full width on top.
      if (constraints.maxWidth < 400) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            accept,
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: reject),
              const SizedBox(width: 8),
              Expanded(child: reschedule),
            ]),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: reject),
          const SizedBox(width: 8),
          Expanded(child: reschedule),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: accept),
        ],
      );
    });
  }

  void _showRescheduleDialog(BuildContext context) {
    // Open-ended requests have no slot yet: default to tomorrow, 10:00.
    final base = appointment.scheduledAt ??
        DateTime.now().copyWith(
            hour: 10, minute: 0, second: 0, millisecond: 0, microsecond: 0);
    var date = base.add(const Duration(days: 1));
    var time = TimeOfDay.fromDateTime(base);
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

}

/// Upcoming appointment: open its Case page (where the case is worked,
/// closed and completed) or record a no-show. "Mark Complete" used to live
/// here; it is now on the Case page only.
class _UpcomingActions extends StatefulWidget {
  final DoctorAppointment appointment;
  const _UpcomingActions({required this.appointment});

  @override
  State<_UpcomingActions> createState() => _UpcomingActionsState();
}

class _UpcomingActionsState extends State<_UpcomingActions> {
  bool _busy = false;

  Future<void> _noShow() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as no-show?'),
        content: const Text(
            'Use this only if the farmer did not attend the appointment.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Mark no-show')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final error = await DoctorSession.instance.updateAppointmentStatus(
        widget.appointment.id, AppointmentStatus.noShow);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ?? 'Marked as no-show.'),
      backgroundColor: error == null ? VetColors.textSecondary : VetColors.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final caseId = widget.appointment.caseId;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('scheduleNoShow'),
            onPressed: _busy ? null : _noShow,
            icon: const Icon(Icons.person_off_outlined, size: 15),
            label: const Text('No-Show', maxLines: 1, softWrap: false),
            style: OutlinedButton.styleFrom(
              foregroundColor: VetColors.red,
              side: BorderSide(color: VetColors.red.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            key: const Key('scheduleOpenCase'),
            onPressed: caseId == null
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CaseDetailScreen(caseId: caseId))),
            icon: const Icon(Icons.folder_open_outlined, size: 15),
            label: const Text('Open case', maxLines: 1, softWrap: false),
            style: ElevatedButton.styleFrom(
              backgroundColor: VetColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }
}


/// Shown when the last refresh failed. Keeps whatever real data is already on
/// screen (a failed background refresh never erases it) and offers Retry.
class _RefreshErrorBanner extends StatelessWidget {
  const _RefreshErrorBanner({required this.message, required this.hasData});
  final String message;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('doctorAppointmentsError'),
      width: double.infinity,
      color: VetColors.redLight,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(children: [
        const Icon(Icons.error_outline, color: VetColors.red, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                hasData
                    ? 'Could not refresh — showing the last loaded data.'
                    : 'Could not load your consultations.',
                style: const TextStyle(
                    color: VetColors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
              // The server's own reason (e.g. a suspended account or an
              // expired sign-in), never a generic "something went wrong".
              Text(
                message.split('\n').first,
                key: const Key('doctorAppointmentsErrorReason'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: VetColors.red, fontSize: 11),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: DoctorSession.instance.refresh,
          child: const Text('Retry'),
        ),
      ]),
    );
  }
}
