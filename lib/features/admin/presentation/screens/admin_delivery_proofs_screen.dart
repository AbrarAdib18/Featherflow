import 'package:flutter/material.dart';
import '../../../../core/network/authed_image.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/admin_api_service.dart';
import '../../data/services/admin_session.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';

/// Delivery proof review queue (F-005). A rider's proof photo never completes
/// an order: an admin approves it here (which completes the order and creates
/// the financial records exactly once) or rejects it with a required reason,
/// after which the rider must resubmit.
class AdminDeliveryProofsScreen extends StatefulWidget {
  const AdminDeliveryProofsScreen({super.key});

  @override
  State<AdminDeliveryProofsScreen> createState() => _AdminDeliveryProofsScreenState();
}

class _AdminDeliveryProofsScreenState extends State<AdminDeliveryProofsScreen> {
  static const _filters = [
    ('submitted', 'Pending review'),
    ('rejected', 'Rejected'),
    ('approved', 'Approved'),
    ('all', 'All'),
  ];

  String _filter = 'submitted';
  List<Map<String, dynamic>> _proofs = [];
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};

  // The server enforces object-level authorization; this only hides buttons
  // the signed-in role could never use.
  bool _canReview(AdminPermission p) {
    final s = AdminSession.instance;
    return s.can(AdminModule.deliveryManagement, p) ||
        s.can(AdminModule.feedDelivery, p) ||
        s.can(AdminModule.pharmacyManagement, p);
  }

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
      final rows = await AdminApiService.instance.deliveryProofs(status: _filter);
      if (!mounted) return;
      setState(() {
        _proofs = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AColors.red : AColors.green,
    ));
  }

  Future<void> _approve(Map<String, dynamic> proof) async {
    final id = proof['id'].toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve delivery proof?'),
        content: Text(
            'Order ${proof['order_number']} will be marked completed and the rider\'s earning recorded.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('confirmApproveButton'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve & complete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy.add(id));
    try {
      await AdminApiService.instance.approveDeliveryProof(id);
      if (!mounted) return;
      _toast('Proof approved — order completed.');
      await _load();
    } catch (error) {
      if (mounted) _toast(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _reject(Map<String, dynamic> proof) async {
    final id = proof['id'].toString();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => _RejectDialog(orderNumber: proof['order_number'].toString()),
    );
    if (reason == null || !mounted) return;
    setState(() => _busy.add(id));
    try {
      await AdminApiService.instance.rejectDeliveryProof(id, reason);
      if (!mounted) return;
      _toast('Proof rejected — the rider was asked to resubmit.');
      await _load();
    } catch (error) {
      if (mounted) _toast(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _openHistory(Map<String, dynamic> proof) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _HistoryDialog(proofId: proof['id'].toString()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when the admin's permissions finish loading (on a fresh page load
    // the list can arrive before /admin-panel/me/, which used to leave the
    // Approve/Reject buttons hidden until a manual refresh).
    return ListenableBuilder(
      listenable: AdminSession.instance,
      builder: (context, _) => _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    return AdminScaffold(
      title: 'Delivery Proofs',
      module: AdminModule.feedDelivery,
      appBarActions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: _load,
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (value, label) in _filters)
                  ChoiceChip(
                    key: Key('proofFilter_$value'),
                    label: Text(label),
                    selected: _filter == value,
                    onSelected: (_) {
                      setState(() => _filter = value);
                      _load();
                    },
                  ),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AColors.secondary));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                key: const Key('proofsError'),
                style: const TextStyle(color: AColors.red, fontSize: 13)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_proofs.isEmpty) {
      return Center(
        child: Text(
          _filter == 'submitted'
              ? 'No delivery proofs are waiting for review.'
              : 'No delivery proofs here yet.',
          key: const Key('proofsEmpty'),
          style: const TextStyle(color: AColors.textSecondary, fontSize: 13),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _proofs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _proofCard(_proofs[i]),
    );
  }

  Widget _proofCard(Map<String, dynamic> proof) {
    final id = proof['id'].toString();
    final status = proof['status']?.toString() ?? '';
    final pending = status == 'submitted';
    final busy = _busy.contains(id);
    final url = proof['url']?.toString() ?? '';
    final (chipLabel, chipColor) = switch (status) {
      'submitted' => ('Pending review', AColors.orange),
      'approved' => ('Approved', AColors.green),
      'rejected' => ('Rejected', AColors.red),
      _ => (status, AColors.grey),
    };
    return Container(
      key: Key('proofCard_$id'),
      decoration: aCard(),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Order ${proof['order_number']}  ·  attempt ${proof['attempt']}',
                  style: const TextStyle(
                      color: AColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: chipColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(chipLabel,
                    style: TextStyle(
                        color: chipColor, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${proof['order_type'] == 'feed' ? 'Feed' : 'Pharmacy'} delivery · rider ${proof['rider']} · '
            'to ${proof['destination']}',
            style: const TextStyle(color: AColors.textSecondary, fontSize: 12),
          ),
          if ((proof['customer'] ?? '').toString().isNotEmpty)
            Text('Customer: ${proof['customer']}',
                style: const TextStyle(color: AColors.textSecondary, fontSize: 12)),
          if ((proof['note'] ?? '').toString().isNotEmpty)
            Text('Rider note: ${proof['note']}',
                style: const TextStyle(color: AColors.textSecondary, fontSize: 12)),
          if (status == 'rejected')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Rejection reason: ${proof['review_reason']}',
                  key: Key('proofReason_$id'),
                  style: const TextStyle(color: AColors.red, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          if (url.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image(
                image: AuthedNetworkImage(url),
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 80,
                  color: AColors.surface2,
                  alignment: Alignment.center,
                  child: const Text('Proof photo unavailable',
                      style: TextStyle(color: AColors.textSecondary, fontSize: 12)),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                key: Key('historyButton_$id'),
                onPressed: () => _openHistory(proof),
                icon: const Icon(Icons.history, size: 16),
                label: const Text('History'),
              ),
              if (pending && _canReview(AdminPermission.approve))
                FilledButton.icon(
                  key: Key('approveButton_$id'),
                  onPressed: busy ? null : () => _approve(proof),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Approve'),
                  style: FilledButton.styleFrom(backgroundColor: AColors.green),
                ),
              if (pending && _canReview(AdminPermission.reject))
                OutlinedButton.icon(
                  key: Key('rejectButton_$id'),
                  onPressed: busy ? null : () => _reject(proof),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(foregroundColor: AColors.red),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RejectDialog extends StatefulWidget {
  final String orderNumber;
  const _RejectDialog({required this.orderNumber});

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => _controller.text.trim().length >= 3;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reject proof for ${widget.orderNumber}'),
      content: TextField(
        key: const Key('rejectReasonField'),
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Reason (required)',
          hintText: 'Tell the rider what to fix, e.g. photo is blurry',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const Key('confirmRejectButton'),
          onPressed: _valid ? () => Navigator.pop(context, _controller.text.trim()) : null,
          style: FilledButton.styleFrom(backgroundColor: AColors.red),
          child: const Text('Reject proof'),
        ),
      ],
    );
  }
}

class _HistoryDialog extends StatefulWidget {
  final String proofId;
  const _HistoryDialog({required this.proofId});

  @override
  State<_HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<_HistoryDialog> {
  Map<String, dynamic>? _detail;
  String? _error;

  @override
  void initState() {
    super.initState();
    AdminApiService.instance.deliveryProofDetail(widget.proofId).then((d) {
      if (mounted) setState(() => _detail = d);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return AlertDialog(
      title: const Text('Proof & state history'),
      content: SizedBox(
        width: 420,
        child: _error != null
            ? Text(_error!, style: const TextStyle(color: AColors.red))
            : detail == null
                ? const SizedBox(
                    height: 60, child: Center(child: CircularProgressIndicator()))
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Proof attempts',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        for (final p in (detail['proofs'] as List? ?? const []))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(
                              'Attempt ${p['attempt']}: ${p['status']}'
                              '${(p['review_reason'] ?? '').toString().isNotEmpty ? ' — ${p['review_reason']}' : ''}'
                              '${p['reviewed_by'] != null ? ' (by ${p['reviewed_by']})' : ''}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        const SizedBox(height: 10),
                        const Text('State history',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        for (final e in (detail['events'] as List? ?? const []))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(
                              '${e['label']} · ${e['actor'] ?? 'system'}'
                              '${(e['note'] ?? '').toString().isNotEmpty ? ' — ${e['note']}' : ''}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}
