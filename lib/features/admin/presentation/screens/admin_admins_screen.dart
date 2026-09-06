import 'package:flutter/material.dart';

import '../../data/models/admin_role.dart';
import '../../data/services/admin_api_service.dart';
import '../../data/services/admin_session.dart';
import '../admin_theme.dart';
import '../widgets/admin_dialogs.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/admin_states.dart';

class AdminAdminsScreen extends StatefulWidget {
  const AdminAdminsScreen({super.key});

  @override
  State<AdminAdminsScreen> createState() => _AdminAdminsScreenState();
}

class _AdminAdminsScreenState extends State<AdminAdminsScreen> {
  List<Map<String, dynamic>> _admins = [];
  List<Map<String, dynamic>> _roles = [];
  bool _loading = true;
  String? _error;

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
      final results = await Future.wait([
        AdminApiService.instance.admins(),
        AdminApiService.instance.roles(),
      ]);
      if (!mounted) return;
      setState(() {
        _admins = results[0];
        _roles = results[1];
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

  List<String> get _assignableRoleNames => _roles
      .map((r) => r['name'].toString())
      .where((n) => n != 'admin_super')
      .toList();

  Future<void> _action(Map<String, dynamic> admin, String action) async {
    String reason = '';
    if (action == 'suspend' || action == 'reject') {
      final r = await showAdminTextPrompt(context,
          title: '${action[0].toUpperCase()}${action.substring(1)} ${admin['name']}',
          label: 'Reason', actionLabel: 'Confirm');
      if (r == null) return;
      reason = r;
    }
    try {
      await AdminApiService.instance
          .adminAction(admin['id'].toString(), action, reason: reason);
      if (!mounted) return;
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AColors.red));
    }
  }

  Future<void> _changeRole(Map<String, dynamic> admin) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AColors.bg,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: [
          for (final name in _assignableRoleNames)
            ListTile(
              title: Text(_roleLabel(name)),
              trailing: admin['role'] == name
                  ? const Icon(Icons.check, color: AColors.secondary)
                  : null,
              onTap: () => Navigator.pop(context, name),
            ),
        ],
      ),
    );
    if (selected == null || selected == admin['role']) return;
    try {
      await AdminApiService.instance
          .updateAdmin(admin['id'].toString(), {'role': selected});
      if (!mounted) return;
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AColors.red));
    }
  }

  String _roleLabel(String name) {
    final match = _roles.firstWhere((r) => r['name'] == name, orElse: () => {});
    return match['display_name']?.toString() ??
        kRoleDisplayNames[adminRoleFromName(name)] ??
        name;
  }

  Future<void> _create() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AColors.bg,
      builder: (ctx) => _CreateAdminSheet(roleNames: _assignableRoleNames, label: _roleLabel),
    );
    if (result == null) return;
    try {
      await AdminApiService.instance.createAdmin(result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Admin account created'), backgroundColor: AColors.green));
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
    final canCreate = session.isSuperAdmin;
    final canReview = session.isOperationsAdmin;
    final pending = _admins.where((a) => a['approval_status'] == 'pending').toList();
    final active = _admins.where((a) => a['approval_status'] != 'pending').toList();

    return AdminScaffold(
      title: 'Admin Management',
      module: AdminModule.adminManagement,
      appBarActions: [
        if (canCreate)
          TextButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.person_add_alt, size: 16, color: AColors.secondary),
            label: const Text('Add Admin',
                style: TextStyle(color: AColors.secondary, fontSize: 13)),
          ),
        IconButton(
            icon: const Icon(Icons.refresh, size: 20), onPressed: _load),
      ],
      child: _loading
          ? const AdminLoading()
          : _error != null
              ? AdminError(_error!, _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (pending.isNotEmpty) ...[
                        const _GroupHeader('Pending registrations'),
                        for (final a in pending)
                          _AdminCard(
                            admin: a,
                            roleLabel: _roleLabel(a['role']?.toString() ?? ''),
                            canReview: canReview,
                            canManage: canCreate,
                            onAction: (act) => _action(a, act),
                            onChangeRole: () => _changeRole(a),
                          ),
                        const SizedBox(height: 12),
                      ],
                      const _GroupHeader('Admin accounts'),
                      if (active.isEmpty)
                        const AdminEmpty('No admin accounts')
                      else
                        for (final a in active)
                          _AdminCard(
                            admin: a,
                            roleLabel: _roleLabel(a['role']?.toString() ?? ''),
                            canReview: canReview,
                            canManage: canCreate,
                            onAction: (act) => _action(a, act),
                            onChangeRole: () => _changeRole(a),
                          ),
                    ],
                  ),
                ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;
  const _GroupHeader(this.label);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: AColors.textSecondary)),
      );
}

class _AdminCard extends StatelessWidget {
  final Map<String, dynamic> admin;
  final String roleLabel;
  final bool canReview;
  final bool canManage;
  final void Function(String action) onAction;
  final VoidCallback onChangeRole;

  const _AdminCard({
    required this.admin,
    required this.roleLabel,
    required this.canReview,
    required this.canManage,
    required this.onAction,
    required this.onChangeRole,
  });

  @override
  Widget build(BuildContext context) {
    final pending = admin['approval_status'] == 'pending';
    final suspended = admin['is_suspended'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: aCard(highlight: pending),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AColors.primary.withValues(alpha: 0.1),
                child: Text(
                  (admin['name']?.toString() ?? '?').characters.first.toUpperCase(),
                  style: const TextStyle(
                      color: AColors.primary, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(admin['name']?.toString() ?? '',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(admin['email']?.toString() ?? '',
                        style: const TextStyle(
                            fontSize: 11, color: AColors.textSecondary)),
                  ],
                ),
              ),
              aChip(
                suspended ? 'Suspended' : (pending ? 'Pending' : 'Active'),
                suspended ? AColors.red : (pending ? AColors.amber : AColors.green),
                suspended ? AColors.red : (pending ? AColors.amber : AColors.green),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            aChip(roleLabel, AColors.blue, AColors.blue),
            aChip('Tier ${admin['tier'] ?? '?'}', AColors.purple, AColors.purple),
            if ((admin['department'] ?? '').toString().isNotEmpty)
              aChip(admin['department'].toString(), AColors.grey, AColors.grey),
          ]),
          if (canReview || canManage) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              if (pending && canReview) ...[
                FilledButton(
                  onPressed: () => onAction('approve'),
                  style: FilledButton.styleFrom(
                      backgroundColor: AColors.green, visualDensity: VisualDensity.compact),
                  child: const Text('Approve'),
                ),
                OutlinedButton(
                  onPressed: () => onAction('reject'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AColors.red, visualDensity: VisualDensity.compact),
                  child: const Text('Reject'),
                ),
              ],
              if (!pending && canManage)
                TextButton(onPressed: onChangeRole, child: const Text('Change Role')),
              if (!pending && canReview)
                TextButton(
                  onPressed: () => onAction(suspended ? 'recover' : 'suspend'),
                  style: TextButton.styleFrom(
                      foregroundColor: suspended ? AColors.green : AColors.red),
                  child: Text(suspended ? 'Recover' : 'Suspend'),
                ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _CreateAdminSheet extends StatefulWidget {
  final List<String> roleNames;
  final String Function(String) label;
  const _CreateAdminSheet({required this.roleNames, required this.label});

  @override
  State<_CreateAdminSheet> createState() => _CreateAdminSheetState();
}

class _CreateAdminSheetState extends State<_CreateAdminSheet> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _jobTitle = TextEditingController();
  final _department = TextEditingController(text: 'Operations');
  late String _role = widget.roleNames.isNotEmpty ? widget.roleNames.first : 'admin_support';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _jobTitle.dispose();
    _department.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Add Admin Account',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          _field(_name, 'Full name'),
          _field(_email, 'Email'),
          _field(_jobTitle, 'Job title'),
          _field(_department, 'Department'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Role', filled: true),
            items: [
              for (final n in widget.roleNames)
                DropdownMenuItem(value: n, child: Text(widget.label(n))),
            ],
            onChanged: (v) => setState(() => _role = v!),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                if (_email.text.trim().isEmpty) return;
                Navigator.pop(context, {
                  'name': _name.text.trim(),
                  'email': _email.text.trim(),
                  'job_title': _jobTitle.text.trim(),
                  'department': _department.text.trim(),
                  'role': _role,
                });
              },
              style: FilledButton.styleFrom(backgroundColor: AColors.primary),
              child: const Text('Create'),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'A temporary password is set; the admin resets it on first sign-in.',
            style: TextStyle(fontSize: 11, color: AColors.grey),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          decoration: InputDecoration(
              labelText: label, filled: true, fillColor: AColors.surface2, isDense: true),
        ),
      );
}
