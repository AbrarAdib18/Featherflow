import 'package:flutter/material.dart';

import '../../data/models/admin_role.dart';
import '../../data/services/admin_api_service.dart';
import '../../data/services/admin_session.dart';
import '../admin_theme.dart';
import '../widgets/admin_dialogs.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/admin_states.dart';

/// Operations / Super view: platform-wide admin activity + the escalation queue.
class AdminOversightScreen extends StatefulWidget {
  const AdminOversightScreen({super.key});

  @override
  State<AdminOversightScreen> createState() => _AdminOversightScreenState();
}

class _AdminOversightScreenState extends State<AdminOversightScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  Map<String, dynamic> _oversight = {};
  List<Map<String, dynamic>> _escalations = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        AdminApiService.instance.oversight(),
        AdminApiService.instance.escalations(status: 'active'),
      ]);
      if (!mounted) return;
      setState(() {
        _oversight = results[0] as Map<String, dynamic>;
        _escalations = results[1] as List<Map<String, dynamic>>;
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

  Future<void> _resolve(Map<String, dynamic> e, String action) async {
    String resolution = '';
    if (action == 'resolve') {
      final r = await showAdminTextPrompt(context,
          title: 'Resolve escalation',
          label: 'Resolution note',
          actionLabel: 'Resolve');
      if (r == null) return;
      resolution = r;
    }
    try {
      await AdminApiService.instance
          .resolveEscalation(e['id'].toString(), action: action, resolution: resolution);
      if (!mounted) return;
      _load();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err.toString()), backgroundColor: AColors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Oversight',
      module: AdminModule.oversight,
      appBarActions: [
        IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _load),
      ],
      child: Column(
        children: [
          Container(
            color: AColors.appBar,
            child: TabBar(
              controller: _tabs,
              indicatorColor: AColors.secondary,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              tabs: const [Tab(text: 'Activity'), Tab(text: 'Escalations')],
            ),
          ),
          Expanded(
            child: _loading
                ? const AdminLoading()
                : _error != null
                    ? AdminError(_error!, _load)
                    : TabBarView(
                        controller: _tabs,
                        children: [
                          _ActivityTab(data: _oversight),
                          _EscalationsTab(
                            rows: _escalations,
                            canResolve: AdminSession.instance.isOperationsAdmin,
                            onResolve: (e) => _resolve(e, 'resolve'),
                            onClaim: (e) => _resolve(e, 'claim'),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _ActivityTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ActivityTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final backlog = (data['module_backlog'] as Map?)?.cast<String, dynamic>() ?? {};
    final byAdmin = (data['activity_by_admin'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final byModule = (data['activity_by_module'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Stat('Pending approvals', data['pending_approvals']),
          _Stat('Open escalations', data['open_escalations']),
          _Stat('Admin registrations', data['pending_admin_registrations']),
        ]),
        const SizedBox(height: 16),
        _Panel(
          title: 'Module backlog',
          child: Column(
            children: [
              for (final entry in backlog.entries)
                _Row(entry.key.replaceAll('_', ' '), '${entry.value}'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Panel(
          title: 'Actions by admin (7 days)',
          child: Column(
            children: [
              for (final r in byAdmin)
                _Row(r['admin']?.toString() ?? '—', '${r['actions']}'),
              if (byAdmin.isEmpty) const _Row('No activity', ''),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Panel(
          title: 'Actions by module (7 days)',
          child: Column(
            children: [
              for (final r in byModule)
                _Row(r['module']?.toString() ?? '—', '${r['actions']}'),
              if (byModule.isEmpty) const _Row('No activity', ''),
            ],
          ),
        ),
      ],
    );
  }
}

class _EscalationsTab extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final bool canResolve;
  final void Function(Map<String, dynamic>) onResolve;
  final void Function(Map<String, dynamic>) onClaim;

  const _EscalationsTab({
    required this.rows,
    required this.canResolve,
    required this.onResolve,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const AdminEmpty('No open escalations');
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final e = rows[i];
        final priority = e['priority']?.toString() ?? 'medium';
        final color = {
          'critical': AColors.red,
          'high': AColors.orange,
          'medium': AColors.amber,
          'low': AColors.grey,
        }[priority] ?? AColors.grey;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: aCard(highlight: priority == 'critical'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(e['subject']?.toString() ?? '',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                  aChip(priority, color, color),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${e['module']} · raised by ${e['raised_by']}'
                '${e['assigned_to'] != null ? ' · assigned to ${e['assigned_to']}' : ''}',
                style: const TextStyle(fontSize: 11, color: AColors.textSecondary),
              ),
              if ((e['detail'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(e['detail'].toString(),
                    style: const TextStyle(fontSize: 12, color: AColors.textPrimary)),
              ],
              if (canResolve) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, children: [
                  if (e['status'] != 'in_progress')
                    OutlinedButton(
                      onPressed: () => onClaim(e),
                      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: const Text('Claim'),
                    ),
                  FilledButton(
                    onPressed: () => onResolve(e),
                    style: FilledButton.styleFrom(
                        backgroundColor: AColors.green, visualDensity: VisualDensity.compact),
                    child: const Text('Resolve'),
                  ),
                ]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final Object? value;
  const _Stat(this.label, this.value);
  @override
  Widget build(BuildContext context) => Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: aCard(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${value ?? 0}',
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: AColors.primary)),
            Text(label,
                style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
          ],
        ),
      );
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;
  const _Panel({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: aCard(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
                child: Text(label,
                    style: const TextStyle(fontSize: 12, color: AColors.textSecondary))),
            Text(value,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
          ],
        ),
      );
}
