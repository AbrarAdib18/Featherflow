import 'package:flutter/material.dart';

import '../../data/models/admin_role.dart';
import '../../data/services/admin_api_service.dart';
import '../../data/services/admin_session.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/admin_dialogs.dart';

class AdminApprovalsScreen extends StatefulWidget {
  const AdminApprovalsScreen({super.key});

  @override
  State<AdminApprovalsScreen> createState() => _AdminApprovalsScreenState();
}

class _AdminApprovalsScreenState extends State<AdminApprovalsScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String _status = 'pending';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AdminApiService.instance.approvalQueue(status: _status);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _decide(Map<String, dynamic> row, String decision) async {
    String rejectionReason = '';
    if (decision == 'reject') {
      final reason = await showAdminTextPrompt(context,
          title: 'Reject request',
          label: 'Reason for rejection',
          actionLabel: 'Reject');
      if (reason == null) return;
      rejectionReason = reason;
    }
    try {
      await AdminApiService.instance
          .decideApproval(row['id'].toString(), decision, rejectionReason: rejectionReason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Request ${decision == 'reject' ? 'rejected' : 'approved'}'),
          backgroundColor: AColors.green));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AColors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AdminSession.instance;
    final canDecide = session.can(AdminModule.approvals, AdminPermission.approve);
    return AdminScaffold(
      title: 'Approval Queue',
      module: AdminModule.approvals,
      appBarActions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: _load,
        ),
      ],
      child: Column(
        children: [
          _StatusTabs(
            value: _status,
            onChanged: (v) {
              setState(() => _status = v);
              _load();
            },
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AColors.secondary))
                : _error != null
                    ? _ErrorState(_error!, _load)
                    : _rows.isEmpty
                        ? const _EmptyState('Nothing in this queue')
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _rows.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) => _QueueCard(
                                row: _rows[i],
                                canDecide: canDecide && _status == 'pending',
                                canOverride: session.isSuperAdmin && _status == 'pending',
                                onApprove: () => _decide(_rows[i], 'approve'),
                                onReject: () => _decide(_rows[i], 'reject'),
                                onOverride: () => _decide(_rows[i], 'override'),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _StatusTabs extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _StatusTabs({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const options = ['pending', 'approved', 'rejected', 'all'];
    return Container(
      color: AColors.appBar,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(o[0].toUpperCase() + o.substring(1)),
                selected: value == o,
                onSelected: (_) => onChanged(o),
                labelStyle: TextStyle(
                    fontSize: 12,
                    color: value == o ? AColors.primary : Colors.white),
                selectedColor: AColors.secondary.withValues(alpha: 0.9),
                backgroundColor: Colors.white10,
              ),
            ),
        ],
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool canDecide;
  final bool canOverride;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onOverride;

  const _QueueCard({
    required this.row,
    required this.canDecide,
    required this.canOverride,
    required this.onApprove,
    required this.onReject,
    required this.onOverride,
  });

  @override
  Widget build(BuildContext context) {
    final status = row['status']?.toString() ?? 'pending';
    final statusColor = {
      'pending': AColors.amber,
      'approved': AColors.green,
      'rejected': AColors.red,
      'overridden': AColors.purple,
    }[status] ?? AColors.grey;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: aCard(highlight: status == 'pending'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${row['action_type']} · ${row['module']}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: AColors.textPrimary),
                ),
              ),
              aChip(status, statusColor, statusColor),
            ],
          ),
          const SizedBox(height: 4),
          Text('Requested by ${row['requested_by']} · needs tier ≤ ${row['required_tier']}',
              style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
          if ((row['reason'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Reason: ${row['reason']}',
                style: const TextStyle(fontSize: 12, color: AColors.textPrimary)),
          ],
          if ((row['rejection_reason'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Rejected: ${row['rejection_reason']}',
                style: const TextStyle(fontSize: 12, color: AColors.red)),
          ],
          if ((row['request_data'] as Map?)?.isNotEmpty ?? false) ...[
            const SizedBox(height: 6),
            Text(row['request_data'].toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AColors.grey)),
          ],
          if (canDecide || canOverride) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                if (canDecide)
                  FilledButton(
                    onPressed: onApprove,
                    style: FilledButton.styleFrom(
                        backgroundColor: AColors.green, visualDensity: VisualDensity.compact),
                    child: const Text('Approve'),
                  ),
                if (canDecide)
                  OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AColors.red, visualDensity: VisualDensity.compact),
                    child: const Text('Reject'),
                  ),
                if (canOverride)
                  TextButton(
                    onPressed: onOverride,
                    style: TextButton.styleFrom(foregroundColor: AColors.purple),
                    child: const Text('Override'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState(this.message);
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 40, color: AColors.grey),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(color: AColors.textSecondary)),
          ],
        ),
      );
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState(this.message, this.onRetry);
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: AColors.red),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AColors.textSecondary)),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}
