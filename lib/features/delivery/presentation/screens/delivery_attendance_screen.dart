import 'package:flutter/material.dart';
import '../delivery_theme.dart';

enum AttendanceStatus { active, onBreak, offline }

class DeliveryAttendanceScreen extends StatefulWidget {
  const DeliveryAttendanceScreen({super.key});

  @override
  State<DeliveryAttendanceScreen> createState() =>
      _DeliveryAttendanceScreenState();
}

class _DeliveryAttendanceScreenState
    extends State<DeliveryAttendanceScreen> {
  AttendanceStatus _status = AttendanceStatus.active;
  DateTime? _checkInTime =
      DateTime.now().subtract(const Duration(hours: 3, minutes: 22));
  DateTime? _checkOutTime;

  // TODO: replace with API call
  static final _mockCalendar = {
    for (int d = 1; d <= 22; d++) d: d % 7 != 0 && d % 7 != 6,
  };
  static const _mockMonth = 'May 2024';

  String get _hoursWorked {
    if (_checkInTime == null) return '0h 0m';
    final end = _checkOutTime ?? DateTime.now();
    final diff = end.difference(_checkInTime!);
    return '${diff.inHours}h ${diff.inMinutes % 60}m';
  }

  void _toggleCheckIn() {
    setState(() {
      if (_status == AttendanceStatus.offline) {
        _status = AttendanceStatus.active;
        _checkInTime = DateTime.now();
        _checkOutTime = null;
      } else {
        _status = AttendanceStatus.offline;
        _checkOutTime = DateTime.now();
      }
    });
  }

  void _toggleBreak() {
    setState(() {
      _status = _status == AttendanceStatus.onBreak
          ? AttendanceStatus.active
          : AttendanceStatus.onBreak;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DColors.bg,
      appBar: AppBar(
        backgroundColor: DColors.appBar,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: const Text(
          'Attendance',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatusCard(),
          const SizedBox(height: 14),
          _buildCheckInButton(),
          const SizedBox(height: 10),
          if (_status != AttendanceStatus.offline) _buildBreakButton(),
          const SizedBox(height: 14),
          _buildTodayLog(),
          const SizedBox(height: 14),
          _buildCalendar(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final (label, color, icon, bgColor) = switch (_status) {
      AttendanceStatus.active => (
          'Active',
          DColors.accent,
          Icons.check_circle,
          DColors.accentLight,
        ),
      AttendanceStatus.onBreak => (
          'On Break',
          DColors.orange,
          Icons.pause_circle,
          DColors.orangeLight,
        ),
      AttendanceStatus.offline => (
          'Offline',
          DColors.grey,
          Icons.cancel,
          DColors.surface2,
        ),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [DColors.primary, DColors.secondaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: DColors.primary.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Current Status',
                  style:
                      TextStyle(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 6),
              Text('Hours Today: $_hoursWorked',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13)),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckInButton() {
    final isCheckedIn = _status != AttendanceStatus.offline;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _toggleCheckIn,
        icon: Icon(isCheckedIn ? Icons.logout : Icons.login, size: 18),
        label: Text(
          isCheckedIn ? 'Check Out' : 'Check In',
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isCheckedIn ? DColors.red : DColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildBreakButton() {
    final onBreak = _status == AttendanceStatus.onBreak;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _toggleBreak,
        icon:
            Icon(onBreak ? Icons.play_arrow : Icons.pause, size: 18),
        label: Text(
          onBreak ? 'Resume Shift' : 'Take Break',
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: DColors.orange,
          side: BorderSide(color: DColors.orange.withValues(alpha: 0.6)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildTodayLog() {
    String fmt(DateTime? dt) {
      if (dt == null) return '—';
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Today's Log",
          style: TextStyle(
              color: DColors.primary,
              fontSize: 15,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: dCard(),
          child: Row(
            children: [
              Expanded(
                child: _logItem(Icons.login, DColors.accent,
                    'Check-In', fmt(_checkInTime)),
              ),
              Container(
                  width: 1, height: 40, color: DColors.cardBorder),
              Expanded(
                child: _logItem(Icons.logout, DColors.red,
                    'Check-Out', fmt(_checkOutTime)),
              ),
              Container(
                  width: 1, height: 40, color: DColors.cardBorder),
              Expanded(
                child: _logItem(Icons.timer_outlined, DColors.accentMid,
                    'Hours', _hoursWorked),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _logItem(
      IconData icon, Color color, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                color: DColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                color: DColors.textSecondary, fontSize: 10)),
      ],
    );
  }

  Widget _buildCalendar() {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Attendance Calendar',
                style: TextStyle(
                    color: DColors.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(_mockMonth,
                style: const TextStyle(
                    color: DColors.textSecondary, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: dCard(),
          child: Column(
            children: [
              Row(
                children: days
                    .map((d) => Expanded(
                          child: Center(
                            child: Text(d,
                                style: const TextStyle(
                                    color: DColors.textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 1,
                ),
                itemCount: 31,
                itemBuilder: (_, i) {
                  final day = i + 1;
                  final present = _mockCalendar[day] ?? false;
                  final isToday = day == 22;
                  return Container(
                    decoration: BoxDecoration(
                      color: isToday
                          ? DColors.primary
                          : present
                              ? DColors.accentLight
                              : DColors.surface2,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isToday
                            ? DColors.primary
                            : present
                                ? DColors.accent.withValues(alpha: 0.4)
                                : DColors.cardBorder,
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$day',
                        style: TextStyle(
                          color: isToday
                              ? Colors.white
                              : present
                                  ? DColors.accent
                                  : DColors.grey,
                          fontSize: 10,
                          fontWeight: isToday
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _legend(DColors.primary, Colors.white, 'Today'),
                  const SizedBox(width: 16),
                  _legend(DColors.accentLight,
                      DColors.accent, 'Present'),
                  const SizedBox(width: 16),
                  _legend(DColors.surface2, DColors.grey, 'Absent'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legend(Color bg, Color textColor, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: DColors.cardBorder),
            ),
          ),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: DColors.textSecondary, fontSize: 10)),
        ],
      );
}
