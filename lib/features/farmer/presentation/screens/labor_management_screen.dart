import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:featherflow/core/theme/theme.dart';
import 'package:intl/intl.dart';
import '../../data/farm_management_service.dart';

class LaborManagementScreen extends StatefulWidget {
  const LaborManagementScreen({super.key});
  @override
  State<LaborManagementScreen> createState() => _LaborManagementScreenState();
}

class _LaborManagementScreenState extends State<LaborManagementScreen> {
  Map<String, dynamic>? data;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await FarmManagementService.get('workers');
      if (mounted)
        setState(() {
          data = result;
          error = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Labor Management',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home, color: Colors.white),
            onPressed: () => context.go('/farmer'),
            tooltip: 'Home',
          ),
        ],
      ),
      body: data == null
          ? Center(
              child: error == null
                  ? const CircularProgressIndicator()
                  : Text(error!))
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SummarySection(data: data!),
                    _AttendanceSection(data: data!, onAction: _workerAction),
                    _PayrollSection(
                        data: data!, onPay: _payWorker, onPayAll: _payAll),
                    _AddWorkerButton(onPressed: _addWorker),
                    _PerformanceSection(data: data!),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              )),
    );
  }

  Future<void> _addWorker() async {
    final name = TextEditingController(),
        phone = TextEditingController(),
        role = TextEditingController(),
        wage = TextEditingController();
    DateTime join = DateTime.now();
    final save = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setLocal) => AlertDialog(
                    title: const Text('Add Worker'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: name,
                          decoration:
                              const InputDecoration(labelText: 'Full name *')),
                      TextField(
                          controller: phone,
                          keyboardType: TextInputType.phone,
                          decoration:
                              const InputDecoration(labelText: 'Phone')),
                      TextField(
                          controller: role,
                          decoration:
                              const InputDecoration(labelText: 'Job role *')),
                      TextField(
                          controller: wage,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Daily wage *')),
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Join date'),
                          subtitle: Text(DateFormat('yyyy-MM-dd').format(join)),
                          onTap: () async {
                            final d = await showDatePicker(
                                context: ctx,
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now(),
                                initialDate: join);
                            if (d != null) setLocal(() => join = d);
                          })
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Save'))
                    ])));
    if (save != true) return;
    try {
      await FarmManagementService.post('workers', {
        'full_name': name.text,
        'phone': phone.text,
        'job_role': role.text,
        'daily_wage': wage.text,
        'join_date': DateFormat('yyyy-MM-dd').format(join)
      });
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _workerAction(String workerId, String action) async {
    try {
      if (['present', 'absent', 'half_day'].contains(action)) {
        await FarmManagementService.patch('workers/attendance', {
          'worker_id': workerId,
          'status': action,
          'attendance_date': DateFormat('yyyy-MM-dd').format(DateTime.now())
        });
      } else if (['active', 'inactive'].contains(action)) {
        await FarmManagementService.patch(
            'workers/detail', {'id': workerId, 'status': action});
      } else if (action == 'delete') {
        final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
                    title: const Text('Remove Worker?'),
                    content: const Text(
                        'This also removes this worker’s attendance, tasks, and payment records.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete'))
                    ]));
        if (ok == true)
          await FarmManagementService.delete(
              'workers/detail', {'id': workerId});
      }
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _payWorker(String id) async {
    await FarmManagementService.post(
        'workers/payments', {'worker_id': id, 'payment_method': 'cash'});
    await _load();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Worker payment recorded.')));
  }

  Future<void> _payAll() async {
    final ids = (data!['workers'] as List).map((x) => x['id']).toList();
    await FarmManagementService.post(
        'workers/payments', {'worker_ids': ids, 'payment_method': 'cash'});
    await _load();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All worker payments recorded.')));
  }
}

class _SummarySection extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SummarySection({required this.data});

  @override
  Widget build(BuildContext context) {
    final s = Map<String, dynamic>.from(data['summary']);
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Workforce Overview',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  label: 'Total Workers',
                  value: '${s['total_workers']}',
                  icon: Icons.people_outline,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _SummaryCard(
                  label: 'Present Today',
                  value: '${s['present_today']}',
                  icon: Icons.check_circle_outline,
                  valueColor: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  label: 'Absent',
                  value: '${s['absent_today']}',
                  icon: Icons.cancel_outlined,
                  valueColor: AppColors.error,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _SummaryCard(
                  label: 'Monthly Payroll',
                  value: '৳${s['monthly_payroll']}',
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color valueColor;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white54, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceSection extends StatelessWidget {
  final Map<String, dynamic> data;
  final void Function(String, String) onAction;
  const _AttendanceSection({required this.data, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final workers = List<Map<String, dynamic>>.from(
        (data['workers'] as List).map((e) => Map<String, dynamic>.from(e)));
    final rows = workers
        .map((w) => _AttendanceData(
            id: w['id'],
            name: w['full_name'],
            role: w['job_role'],
            workerStatus: w['status'],
            checkIn: w['check_in_time'] ?? '—',
            status: w['attendance_status'] == 'present'
                ? _AttendanceStatus.present
                : w['attendance_status'] == 'absent'
                    ? _AttendanceStatus.absent
                    : w['attendance_status'] == 'half_day'
                        ? _AttendanceStatus.halfDay
                        : _AttendanceStatus.notMarked))
        .toList();
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Attendance',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: AppRadius.smAll,
                ),
                child: Text(
                  DateFormat('EEE, dd MMM yyyy').format(DateTime.now()),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppRadius.lgAll,
              border: Border.all(color: const Color(0xFFDEEAE5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                const _AttendanceHeader(),
                const Divider(height: 1, color: Color(0xFFDEEAE5)),
                ...List.generate(
                    rows.length,
                    (i) => Column(
                          children: [
                            _AttendanceRow(
                                data: rows[i],
                                onAction: (value) =>
                                    onAction(rows[i].id, value)),
                            if (i < rows.length - 1)
                              const Divider(
                                  height: 1, color: Color(0xFFDEEAE5)),
                          ],
                        )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceHeader extends StatelessWidget {
  const _AttendanceHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: const BoxDecoration(
        color: Color(0xFFF0F7F4),
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 3, child: _HeaderCell('Name')),
          Expanded(flex: 2, child: _HeaderCell('Role')),
          Expanded(flex: 2, child: _HeaderCell('Check-In')),
          Expanded(flex: 2, child: _HeaderCell('Status')),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;

  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
      ),
    );
  }
}

enum _AttendanceStatus { present, absent, halfDay, notMarked }

class _AttendanceData {
  final String id;
  final String name;
  final String role;
  final String workerStatus;
  final String checkIn;
  final _AttendanceStatus status;

  const _AttendanceData({
    required this.id,
    required this.name,
    required this.role,
    required this.workerStatus,
    required this.checkIn,
    required this.status,
  });
}

class _AttendanceRow extends StatelessWidget {
  final _AttendanceData data;
  final ValueChanged<String> onAction;

  const _AttendanceRow({required this.data, required this.onAction});

  Color get _statusColor {
    switch (data.status) {
      case _AttendanceStatus.present:
        return AppColors.secondary;
      case _AttendanceStatus.absent:
        return AppColors.error;
      case _AttendanceStatus.halfDay:
        return Colors.orange;
      case _AttendanceStatus.notMarked:
        return Colors.grey;
    }
  }

  String get _statusLabel {
    switch (data.status) {
      case _AttendanceStatus.present:
        return 'Present';
      case _AttendanceStatus.absent:
        return 'Absent';
      case _AttendanceStatus.halfDay:
        return 'Half Day';
      case _AttendanceStatus.notMarked:
        return 'Not Marked';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor;
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(data.name,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87)),
              Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: .12),
                      borderRadius: AppRadius.smAll),
                  child: Text(
                      data.workerStatus[0].toUpperCase() +
                          data.workerStatus.substring(1),
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.secondary)))
            ]),
          ),
          Expanded(
            flex: 2,
            child: Text(
              data.role,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              data.checkIn,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          Expanded(
            flex: 2,
            child: PopupMenuButton<String>(
                tooltip: 'Attendance and worker actions',
                onSelected: onAction,
                itemBuilder: (context) => const [
                      PopupMenuItem(
                          value: 'present', child: Text('Mark Present')),
                      PopupMenuItem(
                          value: 'absent', child: Text('Mark Absent')),
                      PopupMenuItem(
                          value: 'half_day', child: Text('Mark Half Day')),
                      PopupMenuDivider(),
                      PopupMenuItem(value: 'active', child: Text('Set Active')),
                      PopupMenuItem(
                          value: 'inactive', child: Text('Set Inactive')),
                      PopupMenuDivider(),
                      PopupMenuItem(
                          value: 'delete', child: Text('Delete Worker'))
                    ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Text(
                    _statusLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                )),
          ),
        ],
      ),
    );
  }
}

class _PayrollSection extends StatelessWidget {
  final Map<String, dynamic> data;
  final ValueChanged<String> onPay;
  final VoidCallback onPayAll;
  const _PayrollSection(
      {required this.data, required this.onPay, required this.onPayAll});

  @override
  Widget build(BuildContext context) {
    final workers = List<Map<String, dynamic>>.from(
        (data['workers'] as List).map((e) => Map<String, dynamic>.from(e)));
    final rows = workers
        .map((w) => _PayrollData(
            id: w['id'],
            name: w['full_name'],
            role: w['job_role'],
            daysWorked: (w['days_worked'] as num).round(),
            salary: '৳${w['salary_due']}'))
        .toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Color(0xFFDEEAE5)),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Payroll',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppRadius.lgAll,
              border: Border.all(color: const Color(0xFFDEEAE5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                const _PayrollHeader(),
                const Divider(height: 1, color: Color(0xFFDEEAE5)),
                ...List.generate(
                    rows.length,
                    (i) => Column(
                          children: [
                            _PayrollRow(
                                data: rows[i], onPay: () => onPay(rows[i].id)),
                            if (i < rows.length - 1)
                              const Divider(
                                  height: 1, color: Color(0xFFDEEAE5)),
                          ],
                        )),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onPayAll,
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: const Text('Pay All Workers'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                shape:
                    const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                textStyle:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _PayrollHeader extends StatelessWidget {
  const _PayrollHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: const BoxDecoration(
        color: Color(0xFFF0F7F4),
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 3, child: _HeaderCell('Worker')),
          Expanded(flex: 2, child: _HeaderCell('Role')),
          Expanded(flex: 1, child: _HeaderCell('Days')),
          Expanded(flex: 2, child: _HeaderCell('Salary')),
          Expanded(flex: 2, child: _HeaderCell('Action')),
        ],
      ),
    );
  }
}

class _PayrollData {
  final String id;
  final String name;
  final String role;
  final int daysWorked;
  final String salary;

  const _PayrollData({
    required this.id,
    required this.name,
    required this.role,
    required this.daysWorked,
    required this.salary,
  });
}

class _PayrollRow extends StatelessWidget {
  final _PayrollData data;
  final VoidCallback onPay;

  const _PayrollRow({required this.data, required this.onPay});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              data.name,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              data.role,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${data.daysWorked}d',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              data.salary,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 28,
              child: ElevatedButton(
                onPressed: onPay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  shape: const RoundedRectangleBorder(
                      borderRadius: AppRadius.smAll),
                  textStyle: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700),
                ),
                child: const Text('Pay'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddWorkerButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _AddWorkerButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.person_add_outlined, size: 18),
          label: const Text('Add Worker'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
            textStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _PerformanceSection extends StatelessWidget {
  final Map<String, dynamic> data;
  const _PerformanceSection({required this.data});

  @override
  Widget build(BuildContext context) {
    final workers = List<Map<String, dynamic>>.from(
        (data['workers'] as List).map((e) => Map<String, dynamic>.from(e)));
    final rows = workers
        .map((w) => _PerformanceData(
            name: w['full_name'],
            tasksCompleted: w['tasks_completed'],
            rating: 0,
            monthlyEarnings: '৳${w['salary_due']}'))
        .toList();
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Color(0xFFDEEAE5)),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Worker Performance',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ...rows.map((w) => _PerformanceCard(data: w)),
        ],
      ),
    );
  }
}

class _PerformanceData {
  final String name;
  final int tasksCompleted;
  final double rating;
  final String monthlyEarnings;

  const _PerformanceData({
    required this.name,
    required this.tasksCompleted,
    required this.rating,
    required this.monthlyEarnings,
  });
}

class _PerformanceCard extends StatelessWidget {
  final _PerformanceData data;

  const _PerformanceCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: const Color(0xFFDEEAE5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Text(
              data.name[0],
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${data.tasksCompleted} tasks completed',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                  const SizedBox(width: 2),
                  Text(
                    data.rating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                data.monthlyEarnings,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
