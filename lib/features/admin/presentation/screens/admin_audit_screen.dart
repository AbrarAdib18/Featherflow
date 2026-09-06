import 'package:flutter/material.dart';

import '../../data/models/admin_role.dart';
import '../../data/models/audit_log.dart';
import '../../data/services/admin_api_service.dart';
import '../../data/services/admin_session.dart';
import '../../data/services/audit_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_dialogs.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/admin_states.dart';

class AdminAuditScreen extends StatefulWidget {
  const AdminAuditScreen({super.key});

  @override
  State<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

class _AdminAuditScreenState extends State<AdminAuditScreen> {
  final _entries = <AuditEntry>[];
  bool _loading = true;
  String? _error;
  int _total = 0;
  int _offset = 0;
  static const _pageSize = 60;

  String? _moduleFilter;
  String? _actionTypeFilter;

  static const _actionTypes = [
    'create', 'edit', 'delete', 'approve', 'reject', 'suspend',
    'assign', 'export', 'refund', 'override', 'login',
    'shift_start', 'shift_end', 'break_start', 'break_end',
    'force_end_shift', 'rate_changed', 'payment_made',
  ];

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _offset = 0;
      _entries.clear();
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AuditService.instance.fetch(
        filters: {
          if (_moduleFilter != null) 'module': _moduleFilter!,
          if (_actionTypeFilter != null) 'action_type': _actionTypeFilter!,
        },
        limit: _pageSize,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _entries.addAll(result.entries);
        _total = result.total;
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

  Future<void> _override(AuditEntry entry) async {
    final reason = await showAdminTextPrompt(context,
        title: 'Override this action',
        label: 'Why are you reversing this?',
        actionLabel: 'Record override');
    if (reason == null) return;
    try {
      final result =
          await AdminApiService.instance.overrideLog(entry.id, reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result['detail']?.toString() ?? 'Override recorded'),
          backgroundColor: AColors.green));
      _load(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AColors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canOverride = AdminSession.instance.isSuperAdmin;
    return AdminScaffold(
      title: 'Audit Trail',
      module: AdminModule.auditTrail,
      appBarActions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: () => _load(reset: true),
        ),
      ],
      child: Column(
        children: [
          _Filters(
            module: _moduleFilter,
            actionType: _actionTypeFilter,
            actionTypes: _actionTypes,
            onModule: (v) {
              setState(() => _moduleFilter = v);
              _load(reset: true);
            },
            onActionType: (v) {
              setState(() => _actionTypeFilter = v);
              _load(reset: true);
            },
          ),
          Expanded(
            child: _entries.isEmpty && _loading
                ? const AdminLoading()
                : _error != null && _entries.isEmpty
                    ? AdminError(_error!, () => _load(reset: true))
                    : _entries.isEmpty
                        ? const AdminEmpty('No audit entries match these filters')
                        : ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: _entries.length + 1,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              if (i == _entries.length) {
                                return _Footer(
                                  shown: _entries.length,
                                  total: _total,
                                  loading: _loading,
                                  onMore: () {
                                    _offset += _pageSize;
                                    _load();
                                  },
                                );
                              }
                              return _AuditCard(
                                entry: _entries[i],
                                canOverride: canOverride &&
                                    _entries[i].actionType != 'override',
                                onOverride: () => _override(_entries[i]),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  final String? module;
  final String? actionType;
  final List<String> actionTypes;
  final ValueChanged<String?> onModule;
  final ValueChanged<String?> onActionType;

  const _Filters({
    required this.module,
    required this.actionType,
    required this.actionTypes,
    required this.onModule,
    required this.onActionType,
  });

  static const _modules = [
    'users', 'doctors', 'delivery-orders', 'riders', 'payouts', 'pharmacies',
    'medicines', 'researchers', 'articles', 'community-reports', 'team',
    'support-tickets', 'escalations', 'payments', 'shifts', 'auth',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AColors.appBar,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: module,
              isExpanded: true,
              dropdownColor: AColors.card,
              decoration: _dec('Module'),
              style: const TextStyle(fontSize: 12, color: AColors.textPrimary),
              items: [
                const DropdownMenuItem(value: null, child: Text('All modules')),
                for (final m in _modules) DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: onModule,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: actionType,
              isExpanded: true,
              dropdownColor: AColors.card,
              decoration: _dec('Action'),
              style: const TextStyle(fontSize: 12, color: AColors.textPrimary),
              items: [
                const DropdownMenuItem(value: null, child: Text('All actions')),
                for (final a in actionTypes) DropdownMenuItem(value: a, child: Text(a)),
              ],
              onChanged: onActionType,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
        filled: true,
        fillColor: Colors.white10,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      );
}

class _AuditCard extends StatelessWidget {
  final AuditEntry entry;
  final bool canOverride;
  final VoidCallback onOverride;

  const _AuditCard({
    required this.entry,
    required this.canOverride,
    required this.onOverride,
  });

  static const _typeColor = {
    'create': AColors.green,
    'edit': AColors.blue,
    'delete': AColors.red,
    'approve': AColors.green,
    'reject': AColors.orange,
    'suspend': AColors.red,
    'assign': AColors.blue,
    'export': AColors.purple,
    'refund': AColors.amber,
    'override': AColors.purple,
  };

  @override
  Widget build(BuildContext context) {
    final color = _typeColor[entry.actionType] ?? AColors.grey;
    final ts = entry.timestamp.toLocal();
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: aCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (entry.actionType.isNotEmpty)
                aChip(entry.actionType, color, color, fontSize: 10),
              const SizedBox(width: 6),
              aChip(entry.module, AColors.grey, AColors.grey, fontSize: 10),
              const Spacer(),
              Text(
                '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')} '
                '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 10, color: AColors.grey),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(entry.action,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AColors.textPrimary)),
          const SizedBox(height: 3),
          Text(
            '${entry.actorName}'
            '${entry.targetId != null ? ' → ${entry.targetId}' : ''}'
            '${entry.ipAddress.isNotEmpty ? ' · ${entry.ipAddress}' : ''}',
            style: const TextStyle(fontSize: 11, color: AColors.textSecondary),
          ),
          if (entry.reason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Reason: ${entry.reason}',
                style: const TextStyle(fontSize: 11, color: AColors.textPrimary)),
          ],
          if (entry.oldValue != null || entry.newValue != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => showAdminDetails(context,
                    title: 'Change detail',
                    icon: Icons.history,
                    fields: [
                      MapEntry('Before', '${entry.oldValue ?? '—'}'),
                      MapEntry('After', '${entry.newValue ?? '—'}'),
                    ]),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
                child: const Text('View change', style: TextStyle(fontSize: 11)),
              ),
            ),
          if (canOverride)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onOverride,
                icon: const Icon(Icons.undo, size: 14),
                label: const Text('Override', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(foregroundColor: AColors.purple),
              ),
            ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final int shown;
  final int total;
  final bool loading;
  final VoidCallback onMore;

  const _Footer({
    required this.shown,
    required this.total,
    required this.loading,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: loading
            ? const CircularProgressIndicator(color: AColors.secondary)
            : shown < total
                ? OutlinedButton(
                    onPressed: onMore,
                    child: Text('Load more ($shown / $total)'),
                  )
                : Text('$shown of $total entries',
                    style: const TextStyle(fontSize: 11, color: AColors.grey)),
      ),
    );
  }
}
