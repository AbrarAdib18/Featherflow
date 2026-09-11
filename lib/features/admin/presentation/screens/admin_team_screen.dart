import 'package:flutter/material.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/audit_service.dart';
import '../../data/services/admin_api_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/permission_guard.dart';
import '../widgets/admin_dialogs.dart';

class AdminTeamScreen extends StatefulWidget {
  const AdminTeamScreen({super.key});

  @override
  State<AdminTeamScreen> createState() => _AdminTeamScreenState();
}

class _AdminTeamScreenState extends State<AdminTeamScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late List<_StaffData> _staff;
  List<_LogEntry> _accessLog = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _staff = [];
    _loadData();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final data = await Future.wait([
        AdminApiService.instance.list('team'),
        AdminApiService.instance.list('access-logs'),
      ]);
      if (!mounted) return;
      setState(() {
        _staff = data[0].map(_StaffData.fromJson).toList();
        _accessLog = data[1].map(_LogEntry.fromJson).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString()), backgroundColor: AColors.red));
    }
  }

  Future<void> _changeRole(String id, String newRole) async {
    final member = _staff.firstWhere((s) => s.id == id);
    final updated = _StaffData.fromJson(await AdminApiService.instance
        .update('team', id, {'role': newRole, 'pending_approval': true}));
    if (!mounted) return;
    setState(() {
      final i = _staff.indexOf(member);
      _staff[i] = updated;
    });
    AuditService.instance.log(
        'Team Management', 'Role Change Request', member.name,
        details: '→ $newRole (awaiting Super Admin approval)');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Role change for ${member.name} sent for Super Admin approval'),
        backgroundColor: AColors.amber,
        duration: const Duration(seconds: 3)));
  }

  Future<void> _deactivate(String id) async {
    final member = _staff.firstWhere((s) => s.id == id);
    final updated = _StaffData.fromJson(await AdminApiService.instance
        .update('team', id, {'status': 'Inactive'}));
    if (!mounted) return;
    setState(() {
      final i = _staff.indexOf(member);
      _staff[i] = updated;
    });
    AuditService.instance.log('Team Management', 'Deactivate', member.name);
  }

  Future<void> _editMember(_StaffData member) async {
    final values = await showAdminRecordEditor(context,
        title: 'Edit Team Member',
        fields: {
          'Name': member.name,
          'Email': member.email,
          'Role': member.role,
          'Department': member.department,
        });
    if (values == null) return;
    final response = await AdminApiService.instance.update('team', member.id, {
      'name': values['Name'],
      'email': values['Email'],
      'role': values['Role'],
      'department': values['Department'],
      'pending_approval': false,
    });
    if (!mounted) return;
    setState(
        () => _staff[_staff.indexOf(member)] = _StaffData.fromJson(response));
  }

  void _showAddMemberSheet() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String selectedRole = kRoleDisplayNames[AdminRole.supportAgent]!;

    showModalBottomSheet(
      context: context,
      backgroundColor: AColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add Team Member',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AColors.textPrimary)),
              const SizedBox(height: 16),
              _InputField('Full Name', nameCtrl, Icons.person_outline),
              const SizedBox(height: 12),
              _InputField('Email', emailCtrl, Icons.email_outlined),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                decoration: InputDecoration(
                  labelText: 'Role',
                  prefixIcon: const Icon(Icons.verified_user_outlined,
                      size: 18, color: AColors.grey),
                  filled: true,
                  fillColor: AColors.surface2,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AColors.cardBorder)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AColors.cardBorder)),
                ),
                items: kRoleDisplayNames.values
                    .where((r) => r != 'Super Admin')
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setLocal(() => selectedRole = v!),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (nameCtrl.text.isNotEmpty && emailCtrl.text.isNotEmpty) {
                      final nav = Navigator.of(ctx);
                      final response =
                          await AdminApiService.instance.create('team', {
                        'name': nameCtrl.text,
                        'email': emailCtrl.text,
                        'role': selectedRole,
                        'department': 'Operations',
                        'status': 'Active',
                        'joined_date': 'Today',
                        'last_active': 'Just now',
                        'pending_approval': false,
                      });
                      final member = _StaffData.fromJson(response);
                      if (!mounted) return;
                      setState(() {
                        _staff.add(member);
                      });
                      AuditService.instance
                          .log('Team Management', 'Add Member', nameCtrl.text);
                      nav.pop();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Add Member',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Team Management',
      module: AdminModule.teamManagement,
      appBarActions: [
        PermissionGuard(
          module: AdminModule.teamManagement,
          permission: AdminPermission.create,
          child: TextButton.icon(
            onPressed: _showAddMemberSheet,
            icon: const Icon(Icons.person_add_outlined,
                size: 16, color: AColors.secondary),
            label: const Text('Add',
                style: TextStyle(
                    color: AColors.secondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ),
        ),
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
              labelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Active Staff'),
                Tab(text: 'Access Log'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AColors.secondary))
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _StaffList(
                          staff: _staff,
                          onChangeRole: _changeRole,
                          onDeactivate: _deactivate,
                          onEdit: _editMember),
                      _AccessLogTab(logs: _accessLog),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Staff list ────────────────────────────────────────────────────────────────

class _StaffList extends StatelessWidget {
  final List<_StaffData> staff;
  final void Function(String, String) onChangeRole;
  final void Function(String) onDeactivate;
  final void Function(_StaffData) onEdit;

  const _StaffList(
      {required this.staff,
      required this.onChangeRole,
      required this.onDeactivate,
      required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: staff.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _StaffCard(
          member: staff[i],
          onChangeRole: onChangeRole,
          onDeactivate: onDeactivate,
          onEdit: onEdit),
    );
  }
}

class _StaffCard extends StatelessWidget {
  final _StaffData member;
  final void Function(String, String) onChangeRole;
  final void Function(String) onDeactivate;
  final void Function(_StaffData) onEdit;

  const _StaffCard(
      {required this.member,
      required this.onChangeRole,
      required this.onDeactivate,
      required this.onEdit});

  void _showRoleSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AColors.bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Change Role for ${member.name}',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AColors.textPrimary)),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                color: AColors.amberLight,
                borderRadius: BorderRadius.circular(8)),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: AColors.amber),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Role changes require Super Admin approval before taking effect.',
                    style: TextStyle(fontSize: 11, color: AColors.orange),
                  ),
                ),
              ],
            ),
          ),
          ...kRoleDisplayNames.entries
              .where((e) => e.key != AdminRole.superAdmin)
              .map((e) => ListTile(
                    leading: Icon(Icons.verified_user_outlined,
                        color: member.role == e.value
                            ? AColors.secondary
                            : AColors.textSecondary,
                        size: 20),
                    title: Text(e.value,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: member.role == e.value
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: member.role == e.value
                                ? AColors.primary
                                : AColors.textPrimary)),
                    trailing: member.role == e.value
                        ? const Icon(Icons.check,
                            color: AColors.secondary, size: 16)
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      onChangeRole(member.id, e.value);
                    },
                  )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isActive = member.status == 'Active';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: aCard(highlight: member.pendingApproval),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AColors.primary.withValues(alpha: 0.1),
                child: Text(member.name[0],
                    style: const TextStyle(
                        color: AColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(member.name,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AColors.textPrimary)),
                    Text(member.email,
                        style: const TextStyle(
                            fontSize: 11, color: AColors.textSecondary)),
                  ],
                ),
              ),
              aChip(
                  isActive ? 'Active' : 'Inactive',
                  isActive ? AColors.green : AColors.grey,
                  isActive ? AColors.green : AColors.grey),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              aChip(member.role, AColors.blue, AColors.blue),
              const SizedBox(width: 8),
              aChip(member.department, AColors.purple, AColors.purple),
              if (member.pendingApproval) ...[
                const SizedBox(width: 8),
                aChip('Pending Approval', AColors.amber, AColors.amber,
                    fontSize: 10),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text('Joined ${member.joinedDate} · Last active ${member.lastActive}',
              style: const TextStyle(fontSize: 10, color: AColors.grey)),
          const SizedBox(height: 10),
          Row(
            children: [
              PermissionGuard(
                module: AdminModule.teamManagement,
                permission: AdminPermission.assign,
                child: _Chip(
                    'Change Role', AColors.blue, () => _showRoleSheet(context)),
              ),
              const SizedBox(width: 8),
              PermissionGuard(
                module: AdminModule.teamManagement,
                permission: AdminPermission.edit,
                child: _Chip('Edit', AColors.grey, () => onEdit(member)),
              ),
              const SizedBox(width: 8),
              if (isActive)
                PermissionGuard(
                  module: AdminModule.teamManagement,
                  permission: AdminPermission.edit,
                  child: _Chip(
                      'Deactivate', AColors.red, () => onDeactivate(member.id)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Access log tab ────────────────────────────────────────────────────────────

class _AccessLogTab extends StatelessWidget {
  final List<_LogEntry> logs;

  const _AccessLogTab({required this.logs});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: logs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final log = logs[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: aCard(),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: AColors.blueLight,
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.history, color: AColors.blue, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(log.action,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AColors.textPrimary)),
                    Text('${log.actor} · ${log.module}',
                        style: const TextStyle(
                            fontSize: 11, color: AColors.textSecondary)),
                  ],
                ),
              ),
              Text(log.time,
                  style: const TextStyle(fontSize: 10, color: AColors.grey)),
            ],
          ),
        );
      },
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _Chip(this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final IconData icon;

  const _InputField(this.label, this.ctrl, this.icon);

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(fontSize: 13, color: AColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AColors.grey, fontSize: 13),
        prefixIcon: Icon(icon, size: 18, color: AColors.grey),
        filled: true,
        fillColor: AColors.surface2,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AColors.cardBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AColors.cardBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AColors.secondary, width: 1.5)),
      ),
    );
  }
}

// ── Mock data ─────────────────────────────────────────────────────────────────

class _StaffData {
  final String id,
      name,
      email,
      role,
      department,
      status,
      joinedDate,
      lastActive;
  final bool pendingApproval;

  const _StaffData({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.department,
    required this.status,
    required this.joinedDate,
    required this.lastActive,
    required this.pendingApproval,
  });

  factory _StaffData.fromJson(Map<String, dynamic> json) => _StaffData(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        role: json['role']?.toString() ?? 'Support Agent',
        department: json['department']?.toString() ?? 'Operations',
        status: json['status']?.toString() ?? 'Active',
        joinedDate: json['joined_date']?.toString() ?? '',
        lastActive: json['last_active']?.toString() ?? '',
        pendingApproval: json['pending_approval'] == true,
      );

  _StaffData copyWith({String? role, String? status, bool? pendingApproval}) =>
      _StaffData(
        id: id,
        name: name,
        email: email,
        role: role ?? this.role,
        department: department,
        status: status ?? this.status,
        joinedDate: joinedDate,
        lastActive: lastActive,
        pendingApproval: pendingApproval ?? this.pendingApproval,
      );
}

class _LogEntry {
  final String actor, action, module, time;

  const _LogEntry(this.actor, this.action, this.module, this.time);

  factory _LogEntry.fromJson(Map<String, dynamic> json) => _LogEntry(
        'Administrator',
        json['action']?.toString() ?? '',
        json['module']?.toString() ?? '',
        json['created_at']
                ?.toString()
                .replaceFirst('T', ' ')
                .split('.')
                .first ??
            '',
      );
}

