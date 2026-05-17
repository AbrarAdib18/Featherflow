import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:featherflow/core/theme/theme.dart';

class LaborManagementScreen extends StatelessWidget {
  const LaborManagementScreen({super.key});

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
      body: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SummarySection(),
            _AttendanceSection(),
            _PayrollSection(),
            _AddWorkerButton(),
            _PerformanceSection(),
            SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.lg,
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Workforce Overview',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  label: 'Total Workers',
                  value: '12',
                  icon: Icons.people_outline,
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _SummaryCard(
                  label: 'Present Today',
                  value: '9',
                  icon: Icons.check_circle_outline,
                  valueColor: AppColors.secondary,
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  label: 'Absent',
                  value: '3',
                  icon: Icons.cancel_outlined,
                  valueColor: AppColors.error,
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _SummaryCard(
                  label: 'Monthly Payroll',
                  value: '৳2.0M',
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
  const _AttendanceSection();

  static const _workers = [
    _AttendanceData(
      name: 'Rahim Uddin',
      role: 'Shed Supervisor',
      checkIn: '06:15 AM',
      status: _AttendanceStatus.present,
    ),
    _AttendanceData(
      name: 'Karim Mia',
      role: 'Feed Operator',
      checkIn: '06:42 AM',
      status: _AttendanceStatus.late,
    ),
    _AttendanceData(
      name: 'Sumaiya Begum',
      role: 'Egg Collector',
      checkIn: '—',
      status: _AttendanceStatus.absent,
    ),
    _AttendanceData(
      name: 'Jamal Hossain',
      role: 'Cleaner',
      checkIn: '06:10 AM',
      status: _AttendanceStatus.present,
    ),
    _AttendanceData(
      name: 'Nasrin Akter',
      role: 'Medicine Handler',
      checkIn: '—',
      status: _AttendanceStatus.absent,
    ),
  ];

  @override
  Widget build(BuildContext context) {
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
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: AppRadius.smAll,
                ),
                child: const Text(
                  'Mon, 12 May 2026',
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
                ...List.generate(_workers.length, (i) => Column(
                  children: [
                    _AttendanceRow(data: _workers[i]),
                    if (i < _workers.length - 1)
                      const Divider(height: 1, color: Color(0xFFDEEAE5)),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
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

enum _AttendanceStatus { present, absent, late }

class _AttendanceData {
  final String name;
  final String role;
  final String checkIn;
  final _AttendanceStatus status;

  const _AttendanceData({
    required this.name,
    required this.role,
    required this.checkIn,
    required this.status,
  });
}

class _AttendanceRow extends StatelessWidget {
  final _AttendanceData data;

  const _AttendanceRow({required this.data});

  Color get _statusColor {
    switch (data.status) {
      case _AttendanceStatus.present:
        return AppColors.secondary;
      case _AttendanceStatus.absent:
        return AppColors.error;
      case _AttendanceStatus.late:
        return Colors.orange;
    }
  }

  String get _statusLabel {
    switch (data.status) {
      case _AttendanceStatus.present:
        return 'Present';
      case _AttendanceStatus.absent:
        return 'Absent';
      case _AttendanceStatus.late:
        return 'Late';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
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
            flex: 2,
            child: Text(
              data.checkIn,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
            ),
          ),
        ],
      ),
    );
  }
}

class _PayrollSection extends StatelessWidget {
  const _PayrollSection();

  static const _workers = [
    _PayrollData(name: 'Rahim Uddin', role: 'Shed Supervisor', daysWorked: 26, salary: '৳18,000'),
    _PayrollData(name: 'Karim Mia', role: 'Feed Operator', daysWorked: 24, salary: '৳14,400'),
    _PayrollData(name: 'Sumaiya Begum', role: 'Egg Collector', daysWorked: 20, salary: '৳10,000'),
    _PayrollData(name: 'Jamal Hossain', role: 'Cleaner', daysWorked: 25, salary: '৳12,500'),
    _PayrollData(name: 'Nasrin Akter', role: 'Medicine Handler', daysWorked: 22, salary: '৳15,400'),
  ];

  @override
  Widget build(BuildContext context) {
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
                ...List.generate(_workers.length, (i) => Column(
                  children: [
                    _PayrollRow(data: _workers[i]),
                    if (i < _workers.length - 1)
                      const Divider(height: 1, color: Color(0xFFDEEAE5)),
                  ],
                )),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: const Text('Pay All Workers'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
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
  final String name;
  final String role;
  final int daysWorked;
  final String salary;

  const _PayrollData({
    required this.name,
    required this.role,
    required this.daysWorked,
    required this.salary,
  });
}

class _PayrollRow extends StatelessWidget {
  final _PayrollData data;

  const _PayrollRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
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
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
                  textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
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
  const _AddWorkerButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.person_add_outlined, size: 18),
          label: const Text('Add Worker'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _PerformanceSection extends StatelessWidget {
  const _PerformanceSection();

  static const _workers = [
    _PerformanceData(
      name: 'Rahim Uddin',
      tasksCompleted: 48,
      rating: 4.8,
      monthlyEarnings: '৳18,000',
    ),
    _PerformanceData(
      name: 'Karim Mia',
      tasksCompleted: 40,
      rating: 4.2,
      monthlyEarnings: '৳14,400',
    ),
    _PerformanceData(
      name: 'Sumaiya Begum',
      tasksCompleted: 32,
      rating: 3.9,
      monthlyEarnings: '৳10,000',
    ),
    _PerformanceData(
      name: 'Jamal Hossain',
      tasksCompleted: 44,
      rating: 4.5,
      monthlyEarnings: '৳12,500',
    ),
    _PerformanceData(
      name: 'Nasrin Akter',
      tasksCompleted: 38,
      rating: 4.1,
      monthlyEarnings: '৳15,400',
    ),
  ];

  @override
  Widget build(BuildContext context) {
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
          ..._workers.map((w) => _PerformanceCard(data: w)),
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
