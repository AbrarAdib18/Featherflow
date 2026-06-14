import 'package:flutter/material.dart';
import '../../data/admin_data.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/audit_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/permission_guard.dart';

class AdminUsersScreen extends StatefulWidget {
  final String initialFilter;
  const AdminUsersScreen({super.key, this.initialFilter = 'All'});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _search = TextEditingController();
  late String _filter;
  late List<AdminUserModel> _users;

  static const _tabLabels = [
    'All', 'Farmers', 'Doctors', 'Delivery', 'Researchers', 'Pharmacy', 'Staff'
  ];
  static const _filters = ['All', 'Pending', 'Approved', 'Suspended'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabLabels.length, vsync: this);
    _users = List.of(kAdminUsers);
    _filter = widget.initialFilter;
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  List<AdminUserModel> _filtered(String? roleTab) {
    final q = _search.text.toLowerCase();
    return _users.where((u) {
      final matchesRole =
          roleTab == null || roleTab == 'All' || u.role == roleTab;
      final matchesFilter =
          _filter == 'All' || u.status == _filter;
      final matchesSearch =
          q.isEmpty || u.name.toLowerCase().contains(q) ||
              u.email.toLowerCase().contains(q);
      return matchesRole && matchesFilter && matchesSearch;
    }).toList();
  }

  void _updateStatus(AdminUserModel user, String newStatus) {
    setState(() {
      final i = _users.indexWhere((u) => u.id == user.id);
      if (i >= 0) _users[i] = user.copyWith(status: newStatus);
    });
    AuditService.instance.log(
      'User Management',
      newStatus == 'Approved' ? 'Approve' : newStatus,
      user.name,
      details: 'Status changed to $newStatus',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${user.name} — $newStatus'),
        backgroundColor: newStatus == 'Approved' ? AColors.green : AColors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showProfile(AdminUserModel user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _UserProfileSheet(user: user, onUpdate: _updateStatus),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'User Management',
      module: AdminModule.userManagement,
      child: Column(
        children: [
          Container(
            color: AColors.appBar,
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AColors.secondary,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
              tabs: _tabLabels.map((t) => Tab(text: t)).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: AColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search by name or email…',
                hintStyle:
                    const TextStyle(color: AColors.grey, fontSize: 14),
                prefixIcon:
                    const Icon(Icons.search, color: AColors.grey, size: 20),
                filled: true,
                fillColor: AColors.surface2,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AColors.cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AColors.cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                      color: AColors.secondary, width: 1.5),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _filters
                  .map((f) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(
                            f,
                            style: TextStyle(
                              fontSize: 12,
                              color: _filter == f
                                  ? Colors.white
                                  : AColors.textSecondary,
                              fontWeight: _filter == f
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          selected: _filter == f,
                          selectedColor: AColors.primary,
                          backgroundColor: AColors.surface2,
                          showCheckmark: false,
                          side: BorderSide(
                              color: _filter == f
                                  ? AColors.primary
                                  : AColors.cardBorder),
                          onSelected: (_) =>
                              setState(() => _filter = f),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _UserList(
                    users: _filtered('All'),
                    onView: _showProfile,
                    onUpdate: _updateStatus),
                ...[
                  'Farmer',
                  'Doctor',
                  'Delivery',
                  'Researcher',
                  'Pharmacy',
                  'Staff'
                ].map((role) => _UserList(
                      users: _filtered(role),
                      onView: _showProfile,
                      onUpdate: _updateStatus,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── User list ─────────────────────────────────────────────────────────────────

class _UserList extends StatelessWidget {
  final List<AdminUserModel> users;
  final void Function(AdminUserModel) onView;
  final void Function(AdminUserModel, String) onUpdate;

  const _UserList(
      {required this.users, required this.onView, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const Center(
        child: Text('No users match the filter.',
            style: TextStyle(color: AColors.textSecondary, fontSize: 13)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) =>
          _UserRow(user: users[i], onView: onView, onUpdate: onUpdate),
    );
  }
}

class _UserRow extends StatelessWidget {
  final AdminUserModel user;
  final void Function(AdminUserModel) onView;
  final void Function(AdminUserModel, String) onUpdate;

  const _UserRow(
      {required this.user, required this.onView, required this.onUpdate});

  Color get _statusColor {
    switch (user.status) {
      case 'Approved':
        return AColors.green;
      case 'Pending':
        return AColors.amber;
      default:
        return AColors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onView(user),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: aCard(),
        child: Row(
          children: [
            CircleAvatar(
            radius: 20,
            backgroundColor: AColors.secondary.withValues(alpha: 0.15),
            child: Text(user.name[0],
                style: const TextStyle(
                    color: AColors.secondary,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(user.name,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AColors.textPrimary),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (user.verified) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified,
                          color: AColors.secondary, size: 13),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(user.role,
                        style: const TextStyle(
                            fontSize: 11, color: AColors.textSecondary)),
                    const SizedBox(width: 8),
                    aChip(user.status, _statusColor, _statusColor,
                        fontSize: 10),
                  ],
                ),
                Text('Joined ${user.joined}',
                    style: const TextStyle(
                        fontSize: 10, color: AColors.grey)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              PermissionGuard(
                module: AdminModule.userManagement,
                permission: AdminPermission.approve,
                child: user.status == 'Pending'
                    ? _ActionBtn('Approve', AColors.secondary,
                        () => onUpdate(user, 'Approved'))
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  PermissionGuard(
                    module: AdminModule.userManagement,
                    permission: AdminPermission.suspend,
                    child: _ActionBtn(
                      user.status == 'Suspended' ? 'Restore' : 'Suspend',
                      user.status == 'Suspended'
                          ? AColors.green
                          : AColors.red,
                      () => onUpdate(
                          user,
                          user.status == 'Suspended'
                              ? 'Approved'
                              : 'Suspended'),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _IconBtn(Icons.visibility_outlined, AColors.blue,
                      () => onView(user)),
                ],
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }
}

// ── User profile sheet ────────────────────────────────────────────────────────

class _UserProfileSheet extends StatelessWidget {
  final AdminUserModel user;
  final void Function(AdminUserModel, String) onUpdate;

  const _UserProfileSheet(
      {required this.user, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: AColors.cardBorder,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AColors.primary,
                child: Text(user.name[0],
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(user.name,
                              style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: AColors.textPrimary)),
                        ),
                        if (user.verified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified,
                              color: AColors.secondary, size: 16),
                        ],
                      ],
                    ),
                    Text(user.email,
                        style: const TextStyle(
                            fontSize: 12, color: AColors.textSecondary)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        aChip(user.role, AColors.blue, AColors.blue),
                        const SizedBox(width: 6),
                        aChip(
                          user.status,
                          user.status == 'Approved'
                              ? AColors.green
                              : user.status == 'Pending'
                                  ? AColors.amber
                                  : AColors.red,
                          user.status == 'Approved'
                              ? AColors.green
                              : user.status == 'Pending'
                                  ? AColors.amber
                                  : AColors.red,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _InfoTile(Icons.phone_outlined, 'Phone', user.phone),
          _InfoTile(Icons.location_on_outlined, 'Location', user.location),
          _InfoTile(Icons.calendar_today_outlined, 'Joined', user.joined),
          _InfoTile(Icons.access_time, 'Last Active', user.lastActive),
          _InfoTile(Icons.info_outline, 'ID', user.id),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: aCard(),
            child: Text(user.bio,
                style: const TextStyle(
                    fontSize: 13, color: AColors.textSecondary, height: 1.5)),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (user.status == 'Pending')
                Expanded(
                  child: PermissionGuard(
                    module: AdminModule.userManagement,
                    permission: AdminPermission.approve,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        onUpdate(user, 'Approved');
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Approve'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AColors.green,
                          foregroundColor: Colors.white),
                    ),
                  ),
                ),
              if (user.status == 'Pending') const SizedBox(width: 10),
              Expanded(
                child: PermissionGuard(
                  module: AdminModule.userManagement,
                  permission: AdminPermission.suspend,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      onUpdate(
                          user,
                          user.status == 'Suspended'
                              ? 'Approved'
                              : 'Suspended');
                      Navigator.pop(context);
                    },
                    icon: Icon(
                        user.status == 'Suspended'
                            ? Icons.restore
                            : Icons.block,
                        size: 16),
                    label: Text(
                        user.status == 'Suspended' ? 'Restore' : 'Suspend'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: user.status == 'Suspended'
                            ? AColors.green
                            : AColors.red,
                        side: BorderSide(
                            color: user.status == 'Suspended'
                                ? AColors.green
                                : AColors.red)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label, value;

  const _InfoTile(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AColors.grey),
          const SizedBox(width: 10),
          Text('$label: ',
              style: const TextStyle(
                  fontSize: 12, color: AColors.textSecondary)),
          Flexible(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

// ── Reusable action widgets ───────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn(this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _IconBtn(this.icon, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Icon(icon, size: 14, color: color),
      ),
    );
  }
}
