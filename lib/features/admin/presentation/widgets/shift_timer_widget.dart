import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/services/admin_session.dart';
import '../admin_theme.dart';

/// Start / End / Break controls + a live HH:MM:SS clock + hours-this-week.
/// Mounted on every hourly admin's dashboard; renders nothing for Super Admin
/// (who is the owner and doesn't track shifts).
class ShiftTimerWidget extends StatefulWidget {
  final bool compact;
  const ShiftTimerWidget({super.key, this.compact = false});

  @override
  State<ShiftTimerWidget> createState() => _ShiftTimerWidgetState();
}

class _ShiftTimerWidgetState extends State<ShiftTimerWidget> {
  Timer? _tick;
  int _baseSeconds = 0;
  DateTime _baseAt = DateTime.now();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AdminSession.instance.addListener(_syncBase);
    AdminSession.instance.refreshShift();
    _syncBase();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && AdminSession.instance.isOnShift && !AdminSession.instance.onBreak) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    AdminSession.instance.removeListener(_syncBase);
    super.dispose();
  }

  void _syncBase() {
    _baseSeconds = AdminSession.instance.shiftSecondsElapsed;
    _baseAt = DateTime.now();
    if (mounted) setState(() {});
  }

  int get _liveSeconds {
    final s = AdminSession.instance;
    if (!s.isOnShift) return 0;
    if (s.onBreak) return _baseSeconds;
    return _baseSeconds + DateTime.now().difference(_baseAt).inSeconds;
  }

  String _fmt(int total) {
    final h = total ~/ 3600, m = (total % 3600) ~/ 60, sec = total % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  Future<void> _do(Future<String?> Function() action) async {
    setState(() => _busy = true);
    final err = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    _syncBase();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: AColors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AdminSession.instance,
      builder: (_, __) {
        final s = AdminSession.instance;
        if (!s.tracksShifts) return const SizedBox.shrink();
        final onShift = s.isOnShift;
        final onBreak = s.onBreak;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: aCard(highlight: onShift),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    onShift ? Icons.timer_outlined : Icons.timer_off_outlined,
                    size: 18,
                    color: onShift ? AColors.secondary : AColors.grey,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    onBreak ? 'On break' : (onShift ? 'On shift' : 'Off shift'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: onBreak
                          ? AColors.amber
                          : (onShift ? AColors.secondary : AColors.textSecondary),
                    ),
                  ),
                  const Spacer(),
                  Text(_fmt(_liveSeconds),
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          fontFeatures: [FontFeature.tabularFigures()],
                          color: AColors.textPrimary)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 4, children: [
                _stat('This week', '${s.hoursThisWeek.toStringAsFixed(2)} h'),
                _stat('This month', '${s.hoursThisMonth.toStringAsFixed(1)} h'),
                _stat('Rate', '৳${s.hourlyRate.toStringAsFixed(0)}/h'),
                if ((s.shift['pending_hourly_rate']) != null)
                  _stat('New rate',
                      '৳${(s.shift['pending_hourly_rate'] as num).toStringAsFixed(0)} · ${s.shift['pending_rate_effective_from']}'),
              ]),
              if (s.shift['over_max_hours'] == true) ...[
                const SizedBox(height: 6),
                Text(
                  '⚠ Over your ${s.shift['max_hours_per_week']} h/week limit — extra hours pay 1.5×.',
                  style: const TextStyle(fontSize: 11, color: AColors.orange),
                ),
              ],
              const SizedBox(height: 10),
              Row(children: [
                if (!onShift)
                  _btn('Start Shift', AColors.secondary, Icons.play_arrow,
                      _busy ? null : () => _do(s.startShift))
                else ...[
                  _btn('End Shift', AColors.red, Icons.stop,
                      _busy ? null : () => _do(s.endShift)),
                  const SizedBox(width: 8),
                  if (!onBreak && s.shift['active_shift']?['break_start'] == null)
                    _btn('Break', AColors.amber, Icons.free_breakfast_outlined,
                        _busy ? null : () => _do(s.startBreak))
                  else if (onBreak)
                    _btn('Resume', AColors.secondary, Icons.play_arrow,
                        _busy ? null : () => _do(s.endBreak)),
                ],
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: AColors.grey)),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
        ],
      );

  Widget _btn(String label, Color color, IconData icon, VoidCallback? onTap) => FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        ),
      );
}
