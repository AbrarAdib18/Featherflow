import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/admin_role.dart';
import '../../data/services/admin_api_service.dart';
import '../../data/services/admin_session.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/admin_states.dart';

/// The logged-in hourly admin's own DB-backed earnings — Today / This Week /
/// This Month / Total Income, at the server-authoritative hourly rate.
///
/// The server (`GET /api/admin-panel/my-shift/earnings/`) is the only source
/// of truth for money: nothing here is computed permanently client-side. The
/// "Today" figure may tick up once a second while a shift is active — a
/// purely local, purely visual extrapolation from the last server fetch (the
/// same convention `ShiftTimerWidget` already uses for its live clock) — but
/// every reconciliation (on entry, after shift start/end, on app resume, on
/// manual refresh, and periodically while a shift is active) replaces it with
/// the real server figure. See OPERATIONS_ADMIN_EARNINGS.md.
class AdminEarningsScreen extends StatefulWidget {
  const AdminEarningsScreen({super.key});

  @override
  State<AdminEarningsScreen> createState() => _AdminEarningsScreenState();
}

class _AdminEarningsScreenState extends State<AdminEarningsScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic> _data = const {};
  bool _loading = true;
  bool _hasLoadedOnce = false;
  String? _error;

  Timer? _reconcile;
  Timer? _tick;
  bool? _wasOnShift;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AdminSession.instance.addListener(_onSessionChanged);
    _wasOnShift = AdminSession.instance.isOnShift;
    _load();
    // A local 1-second tick for display only — see the class doc above.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && AdminSession.instance.isOnShift) setState(() {});
    });
  }

  @override
  void dispose() {
    _reconcile?.cancel();
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    AdminSession.instance.removeListener(_onSessionChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _hasLoadedOnce) {
      _load(silent: true);
    }
  }

  void _onSessionChanged() {
    final onShift = AdminSession.instance.isOnShift;
    if (onShift != _wasOnShift) {
      _wasOnShift = onShift;
      _armReconcile(onShift);
      // After shift start / after shift end — reconcile against the server
      // exactly once the transition itself is seen, not just on the next
      // periodic tick.
      _load(silent: true);
    }
  }

  void _armReconcile(bool onShift) {
    _reconcile?.cancel();
    if (!onShift) return;
    // A safe periodic interval while a shift is active — not a per-second
    // request. The 1-second Timer above only repaints the local estimate;
    // this is the one that actually re-fetches from the server.
    _reconcile = Timer.periodic(
        const Duration(seconds: 20), (_) => _load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final data = await AdminApiService.instance.myEarnings();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        _hasLoadedOnce = true;
        _error = null;
      });
      _armReconcile(_data['active_shift'] != null);
    } catch (e) {
      if (!mounted) return;
      // A failed background refresh must not erase the last valid values —
      // _data is intentionally left untouched here.
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // ── live "Today" extrapolation (display-only) ───────────────────────────

  /// Seconds elapsed in the active shift beyond what the last server fetch
  /// already counted, so the ticking display never double-counts the portion
  /// the server already reported.
  int get _liveDeltaSeconds {
    final active = _data['active_shift'] as Map?;
    if (active == null) return 0;
    final generatedAt = DateTime.tryParse(_data['generated_at']?.toString() ?? '');
    if (generatedAt == null) return 0;
    final delta = DateTime.now().toUtc().difference(generatedAt.toUtc()).inSeconds;
    return delta > 0 ? delta : 0;
  }

  num _rateNum() => double.tryParse(_data['hourly_rate_bdt']?.toString() ?? '') ?? 0;

  Map<String, num> _liveWindow(String key) {
    final window = (_data[key] as Map?) ?? const {};
    final baseSeconds = (window['duration_seconds'] as num?)?.toInt() ?? 0;
    final baseEarnings = double.tryParse(window['earnings_bdt']?.toString() ?? '') ?? 0;
    final delta = _liveDeltaSeconds;
    if (delta == 0) return {'seconds': baseSeconds, 'earnings': baseEarnings};
    final seconds = baseSeconds + delta;
    final earnings = baseEarnings + (delta / 3600.0) * _rateNum();
    return {'seconds': seconds, 'earnings': earnings};
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Earnings',
      module: AdminModule.earnings,
      child: _loading && !_hasLoadedOnce
          ? const AdminLoading()
          : _error != null && !_hasLoadedOnce
              ? AdminError(_error!, () => _load())
              : RefreshIndicator(
                  onRefresh: () => _load(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_error != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: AColors.redLight,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AColors.red.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: AColors.red, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                      'Could not refresh: $_error (showing last loaded data)',
                                      style: const TextStyle(color: AColors.red, fontSize: 12)),
                                ),
                                TextButton(
                                  onPressed: _loading ? null : () => _load(),
                                  child: const Text('Retry', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                        ],
                        _ShiftStatusBanner(data: _data),
                        const SizedBox(height: 12),
                        _EarningsCard(
                          title: 'Today',
                          icon: Icons.today_outlined,
                          seconds: _liveWindow('today')['seconds']!.toInt(),
                          earnings: _liveWindow('today')['earnings']!.toDouble(),
                          rate: _rateNum().toDouble(),
                          live: _data['active_shift'] != null,
                        ),
                        const SizedBox(height: 12),
                        _EarningsCard(
                          title: 'This Week',
                          icon: Icons.date_range_outlined,
                          seconds: _liveWindow('this_week')['seconds']!.toInt(),
                          earnings: _liveWindow('this_week')['earnings']!.toDouble(),
                          rate: _rateNum().toDouble(),
                          live: _data['active_shift'] != null,
                        ),
                        const SizedBox(height: 12),
                        _EarningsCard(
                          title: 'This Month',
                          icon: Icons.calendar_month_outlined,
                          seconds: _liveWindow('this_month')['seconds']!.toInt(),
                          earnings: _liveWindow('this_month')['earnings']!.toDouble(),
                          rate: _rateNum().toDouble(),
                          live: _data['active_shift'] != null,
                        ),
                        const SizedBox(height: 12),
                        _EarningsCard(
                          title: 'Total Income',
                          icon: Icons.account_balance_wallet_outlined,
                          seconds: ((_data['total_income'] as Map?)?['completed_duration_seconds']
                                      as num?)
                                  ?.toInt() ??
                              0,
                          earnings: double.tryParse(
                                  (_data['total_income'] as Map?)?['earnings_bdt']?.toString() ??
                                      '') ??
                              0,
                          rate: _rateNum().toDouble(),
                          live: false,
                          subtitle: 'Completed shifts only — a currently active '
                              'shift is not included here.',
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

String formatDuration(int totalSeconds) {
  final s = totalSeconds < 0 ? 0 : totalSeconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  return '${h}h ${m}m';
}

String formatBdt(num amount) => '৳${amount.toStringAsFixed(2)}';

class _ShiftStatusBanner extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ShiftStatusBanner({required this.data});

  @override
  Widget build(BuildContext context) {
    final active = data['active_shift'] as Map?;
    final onBreak = active?['on_break'] == true;
    final onShift = active != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: aCard(highlight: onShift),
      child: Row(
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
          Text('Rate: ৳${(double.tryParse(data['hourly_rate_bdt']?.toString() ?? '') ?? 0).toStringAsFixed(0)}/hour',
              style: const TextStyle(fontSize: 12, color: AColors.textSecondary)),
        ],
      ),
    );
  }
}

class _EarningsCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final int seconds;
  final double earnings;
  final double rate;
  final bool live;
  final String? subtitle;

  const _EarningsCard({
    required this.title,
    required this.icon,
    required this.seconds,
    required this.earnings,
    required this.rate,
    required this.live,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: aCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AColors.secondary),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
              if (live) ...[
                const SizedBox(width: 8),
                aChip('Live', AColors.secondary, AColors.secondary, fontSize: 10),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(formatDuration(seconds),
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: AColors.textPrimary)),
          const SizedBox(height: 4),
          Text(formatBdt(earnings),
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w800, color: AColors.secondary)),
          const SizedBox(height: 4),
          Text('Rate: ৳${rate.toStringAsFixed(0)}/hour',
              style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!,
                style: const TextStyle(fontSize: 11, color: AColors.grey),
                overflow: TextOverflow.ellipsis,
                maxLines: 2),
          ],
        ],
      ),
    );
  }
}
