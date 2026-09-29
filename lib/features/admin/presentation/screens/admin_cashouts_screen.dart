import 'package:flutter/material.dart';

import '../../data/models/admin_role.dart';
import '../../data/services/admin_api_service.dart';
import '../../data/services/admin_session.dart';
import '../admin_theme.dart';
import '../widgets/admin_dialogs.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/admin_states.dart';

/// Finance Admin's cashout review workflow — see
/// FINANCE_ADMIN_CASHOUT_WORKFLOW.md. [pending] selects which of the two
/// pages this renders: Pending Cashout Requests (requested/under_review,
/// actionable) or Approved Cashout Requests (approved/paid, read-only
/// history). Both pages only ever show cashout-type payments — never user
/// verification or other operational approval records.
class AdminCashoutsScreen extends StatefulWidget {
  final bool pending;
  const AdminCashoutsScreen({super.key, required this.pending});

  @override
  State<AdminCashoutsScreen> createState() => _AdminCashoutsScreenState();
}

class _AdminCashoutsScreenState extends State<AdminCashoutsScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _hasLoadedOnce = false;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = widget.pending
          ? await AdminApiService.instance.pendingCashouts()
          : await AdminApiService.instance.approvedCashouts();
      if (!mounted) return;
      setState(() {
        _rows = (data['results'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
        _hasLoadedOnce = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _review(Map<String, dynamic> row, String decision) async {
    String reason = '';
    if (decision == 'reject') {
      final confirmed = await showAdminTextPrompt(context,
          title: 'Reject cashout request',
          label: 'Reason for rejection',
          actionLabel: 'Reject');
      if (confirmed == null) return;
      reason = confirmed;
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(decision == 'approve' ? 'Approve cashout request' : 'Mark as settled'),
          content: Text(decision == 'approve'
              ? 'Approve this ${row['currency']} ${row['amount']} cashout request?'
              : 'Confirm this cashout has been paid out?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(decision == 'approve' ? 'Approve' : 'Mark paid')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await AdminApiService.instance.reviewCashout(row['id'].toString(), decision, reason: reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cashout request $decision${decision.endsWith('e') ? 'd' : ''}.'),
              backgroundColor: AColors.green));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AColors.red));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AdminSession.instance;
    final module = widget.pending ? AdminModule.cashoutsPending : AdminModule.cashoutsApproved;
    final canReview = session.can(module, AdminPermission.approve);
    return AdminScaffold(
      title: widget.pending ? 'Pending Cashout Requests' : 'Approved Cashout Requests',
      module: module,
      appBarActions: [
        IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh, size: 20), onPressed: _load),
      ],
      child: _loading && !_hasLoadedOnce
          ? const AdminLoading()
          : _error != null && !_hasLoadedOnce
              ? AdminError(_error!, _load)
              : _rows.isEmpty
                  ? AdminEmpty(widget.pending
                      ? 'No cashout requests awaiting review'
                      : 'No approved cashout requests yet')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _CashoutCard(
                          row: _rows[i],
                          pending: widget.pending,
                          canReview: canReview && !_busy,
                          onApprove: () => _review(_rows[i], 'approve'),
                          onReject: () => _review(_rows[i], 'reject'),
                          onSettle: () => _review(_rows[i], 'settle'),
                        ),
                      ),
                    ),
    );
  }
}

class _CashoutCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool pending;
  final bool canReview;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onSettle;

  const _CashoutCard({
    required this.row,
    required this.pending,
    required this.canReview,
    required this.onApprove,
    required this.onReject,
    required this.onSettle,
  });

  @override
  Widget build(BuildContext context) {
    final status = (row['status'] ?? '').toString();
    final statusColor = {
          'requested': AColors.grey,
          'under_review': AColors.amber,
          'approved': AColors.secondary,
          'paid': AColors.green,
          'rejected': AColors.red,
        }[status] ??
        AColors.grey;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: aCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(row['requester_name']?.toString() ?? 'Unknown',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              aChip(status.replaceAll('_', ' '), statusColor, statusColor),
            ],
          ),
          const SizedBox(height: 6),
          Text('${row['currency']} ${row['amount']}',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: AColors.secondary)),
          const SizedBox(height: 4),
          Text('Method: ${row['method'] ?? '—'}  ·  Ref: ${row['reference'] ?? ''}',
              style: const TextStyle(fontSize: 12, color: AColors.textSecondary)),
          if (row['requested_at'] != null)
            Text('Requested: ${row['requested_at']}',
                style: const TextStyle(fontSize: 11, color: AColors.grey)),
          if (!pending && row['reviewed_by'] != null)
            Text('Reviewed by ${row['reviewed_by']} at ${row['reviewed_at'] ?? ''}',
                style: const TextStyle(fontSize: 11, color: AColors.grey)),
          if (canReview) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (pending) ...[
                  FilledButton(
                    onPressed: onApprove,
                    style: FilledButton.styleFrom(backgroundColor: AColors.secondary),
                    child: const Text('Approve'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: onReject, child: const Text('Reject')),
                ] else if (status == 'approved')
                  FilledButton(
                    onPressed: onSettle,
                    style: FilledButton.styleFrom(backgroundColor: AColors.green),
                    child: const Text('Mark Paid'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
