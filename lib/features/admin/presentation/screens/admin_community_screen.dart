import 'package:flutter/material.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/audit_service.dart';
import '../../data/services/admin_api_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/permission_guard.dart';
import '../widgets/admin_dialogs.dart';

class AdminCommunityScreen extends StatefulWidget {
  const AdminCommunityScreen({super.key});

  @override
  State<AdminCommunityScreen> createState() => _AdminCommunityScreenState();
}

class _AdminCommunityScreenState extends State<AdminCommunityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late List<_ReportData> _reports;
  late List<_UserSummary> _users;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _reports = [];
    _users = [];
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
        AdminApiService.instance.list('community-reports'),
        AdminApiService.instance.list('community-users'),
      ]);
      if (!mounted) return;
      setState(() {
        _reports = data[0].map(_ReportData.fromJson).toList();
        _users = data[1].map(_UserSummary.fromJson).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString()), backgroundColor: AColors.red));
    }
  }

  Future<void> _removePost(String id) async {
    final r = _reports.firstWhere((r) => r.id == id);
    final updated = _ReportData.fromJson(await AdminApiService.instance
        .update('community-reports', id, {'status': 'Removed'}));
    if (!mounted) return;
    setState(() {
      final i = _reports.indexOf(r);
      _reports[i] = updated;
    });
    AuditService.instance
        .log('Community Moderation', 'Remove Post', r.postTitle);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Post removed'),
        backgroundColor: AColors.red,
        duration: Duration(seconds: 2)));
  }

  Future<void> _dismissReport(String id) async {
    final r = _reports.firstWhere((r) => r.id == id);
    final updated = _ReportData.fromJson(await AdminApiService.instance
        .update('community-reports', id, {'status': 'Dismissed'}));
    if (!mounted) return;
    setState(() {
      final i = _reports.indexOf(r);
      _reports[i] = updated;
    });
    AuditService.instance
        .log('Community Moderation', 'Dismiss Report', r.postTitle);
  }

  Future<void> _muteUser(String userId) async {
    final updated = _UserSummary.fromJson(await AdminApiService.instance
        .update('community-users', userId, {'muted': true}));
    if (!mounted) return;
    setState(() {
      final i = _users.indexWhere((u) => u.id == userId);
      if (i >= 0) _users[i] = updated;
    });
    final user = _users.firstWhere((u) => u.id == userId);
    AuditService.instance.log('Community Moderation', 'Mute User', user.name);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${user.name} muted'),
        backgroundColor: AColors.orange,
        duration: const Duration(seconds: 2)));
  }

  Future<void> _grantBadge(String userId) async {
    final updated = _UserSummary.fromJson(await AdminApiService.instance
        .update('community-users', userId, {'verified': true}));
    if (!mounted) return;
    setState(() {
      final i = _users.indexWhere((u) => u.id == userId);
      if (i >= 0) _users[i] = updated;
    });
    final user = _users.firstWhere((u) => u.id == userId);
    AuditService.instance.log('Community Moderation', 'Grant Badge', user.name);
  }

  Future<void> _editReport(_ReportData report) async {
    final values = await showAdminRecordEditor(context,
        title: 'Edit Moderation Record',
        fields: {
          'Post title': report.postTitle,
          'Author': report.author,
          'Type': report.type,
          'Excerpt': report.excerpt,
          'Report count': '${report.reportCount}',
          'Date': report.date,
        });
    if (values == null) return;
    final response =
        await AdminApiService.instance.update('community-reports', report.id, {
      'post_title': values['Post title'],
      'author': values['Author'],
      'type': values['Type'],
      'excerpt': values['Excerpt'],
      'report_count':
          int.tryParse(values['Report count'] ?? '') ?? report.reportCount,
      'date': values['Date'],
    });
    if (!mounted) return;
    setState(() =>
        _reports[_reports.indexOf(report)] = _ReportData.fromJson(response));
  }

  Future<void> _editUser(_UserSummary user) async {
    final values = await showAdminRecordEditor(context,
        title: 'Edit Community User',
        fields: {
          'Name': user.name,
          'Post count': '${user.postCount}',
          'Report count': '${user.reportCount}',
        });
    if (values == null) return;
    final response =
        await AdminApiService.instance.update('community-users', user.id, {
      'name': values['Name'],
      'posts': int.tryParse(values['Post count'] ?? '') ?? user.postCount,
      'report_count':
          int.tryParse(values['Report count'] ?? '') ?? user.reportCount,
    });
    if (!mounted) return;
    setState(
        () => _users[_users.indexOf(user)] = _UserSummary.fromJson(response));
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Community Moderation',
      module: AdminModule.communityModeration,
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
                Tab(text: 'Reports'),
                Tab(text: 'Spam Control'),
                Tab(text: 'Users'),
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
                      _ReportsList(
                          reports: _reports
                              .where((r) => r.status == 'Open')
                              .toList(),
                          onRemove: _removePost,
                          onDismiss: _dismissReport,
                          onEdit: _editReport),
                      _SpamList(
                          reports:
                              _reports.where((r) => r.type == 'Spam').toList(),
                          onRemove: _removePost,
                          onDismiss: _dismissReport,
                          onEdit: _editReport),
                      _UserList(
                          users: _users,
                          onMute: _muteUser,
                          onBadge: _grantBadge,
                          onEdit: _editUser),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Reports tab ───────────────────────────────────────────────────────────────

class _ReportsList extends StatelessWidget {
  final List<_ReportData> reports;
  final void Function(String) onRemove;
  final void Function(String) onDismiss;
  final void Function(_ReportData) onEdit;

  const _ReportsList(
      {required this.reports,
      required this.onRemove,
      required this.onDismiss,
      required this.onEdit});

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return const Center(
          child: Text('No open reports.',
              style: TextStyle(color: AColors.textSecondary, fontSize: 13)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: reports.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _ReportCard(
          report: reports[i],
          onRemove: onRemove,
          onDismiss: onDismiss,
          onEdit: onEdit),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final _ReportData report;
  final void Function(String) onRemove;
  final void Function(String) onDismiss;
  final void Function(_ReportData) onEdit;

  const _ReportCard(
      {required this.report,
      required this.onRemove,
      required this.onDismiss,
      required this.onEdit});

  Color get _typeColor {
    switch (report.type) {
      case 'Spam':
        return AColors.orange;
      case 'Harassment':
        return AColors.red;
      case 'Misinformation':
        return AColors.purple;
      default:
        return AColors.amber;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: aCard(highlight: report.reportCount >= 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              aChip(report.type, _typeColor, _typeColor),
              const SizedBox(width: 6),
              aChip('${report.reportCount} reports', AColors.red, AColors.red,
                  fontSize: 10),
              const Spacer(),
              Text(report.date,
                  style: const TextStyle(fontSize: 10, color: AColors.grey)),
            ],
          ),
          const SizedBox(height: 8),
          Text(report.postTitle,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AColors.textPrimary)),
          Text('by ${report.author}',
              style:
                  const TextStyle(fontSize: 11, color: AColors.textSecondary)),
          const SizedBox(height: 4),
          Text(report.excerpt,
              style: const TextStyle(
                  fontSize: 12, color: AColors.grey, height: 1.4),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          Row(
            children: [
              PermissionGuard(
                module: AdminModule.communityModeration,
                permission: AdminPermission.delete,
                child: _Chip(
                    'Remove Post', AColors.red, () => onRemove(report.id)),
              ),
              const SizedBox(width: 8),
              _Chip('Dismiss', AColors.grey, () => onDismiss(report.id)),
              const SizedBox(width: 8),
              _Chip('Edit', AColors.blue, () => onEdit(report)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Spam tab ──────────────────────────────────────────────────────────────────

class _SpamList extends StatelessWidget {
  final List<_ReportData> reports;
  final void Function(String) onRemove;
  final void Function(String) onDismiss;
  final void Function(_ReportData) onEdit;

  const _SpamList(
      {required this.reports,
      required this.onRemove,
      required this.onDismiss,
      required this.onEdit});

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return const Center(
          child: Text('No spam detected.',
              style: TextStyle(color: AColors.textSecondary, fontSize: 13)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: reports.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _ReportCard(
          report: reports[i],
          onRemove: onRemove,
          onDismiss: onDismiss,
          onEdit: onEdit),
    );
  }
}

// ── Users tab ─────────────────────────────────────────────────────────────────

class _UserList extends StatelessWidget {
  final List<_UserSummary> users;
  final void Function(String) onMute;
  final void Function(String) onBadge;
  final void Function(_UserSummary) onEdit;

  const _UserList(
      {required this.users,
      required this.onMute,
      required this.onBadge,
      required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _UserCard(
          user: users[i], onMute: onMute, onBadge: onBadge, onEdit: onEdit),
    );
  }
}

class _UserCard extends StatelessWidget {
  final _UserSummary user;
  final void Function(String) onMute;
  final void Function(String) onBadge;
  final void Function(_UserSummary) onEdit;

  const _UserCard(
      {required this.user,
      required this.onMute,
      required this.onBadge,
      required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: aCard(),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AColors.secondary.withValues(alpha: 0.15),
            child: Text(user.name[0],
                style: const TextStyle(
                    color: AColors.secondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(user.name,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AColors.textPrimary)),
                    if (user.verified) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified,
                          color: AColors.secondary, size: 14),
                    ],
                    if (user.muted) ...[
                      const SizedBox(width: 6),
                      aChip('Muted', AColors.orange, AColors.orange,
                          fontSize: 9),
                    ],
                  ],
                ),
                Text('${user.postCount} posts · ${user.reportCount} reports',
                    style: const TextStyle(
                        fontSize: 11, color: AColors.textSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!user.muted)
                PermissionGuard(
                  module: AdminModule.communityModeration,
                  permission: AdminPermission.suspend,
                  child: _Chip('Mute', AColors.orange, () => onMute(user.id)),
                ),
              const SizedBox(height: 4),
              if (!user.verified)
                PermissionGuard(
                  module: AdminModule.communityModeration,
                  permission: AdminPermission.approve,
                  child: _Chip(
                      'Verify', AColors.secondary, () => onBadge(user.id)),
                ),
              const SizedBox(height: 4),
              _Chip('Edit', AColors.blue, () => onEdit(user)),
            ],
          ),
        ],
      ),
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

// ── Mock data ─────────────────────────────────────────────────────────────────

class _ReportData {
  final String id, postTitle, author, type, status, date, excerpt;
  final int reportCount;

  const _ReportData({
    required this.id,
    required this.postTitle,
    required this.author,
    required this.type,
    required this.status,
    required this.date,
    required this.excerpt,
    required this.reportCount,
  });

  factory _ReportData.fromJson(Map<String, dynamic> json) => _ReportData(
        id: json['id'].toString(),
        postTitle: json['post_title']?.toString() ?? '',
        author: json['author']?.toString() ?? '',
        type: json['type']?.toString() ?? 'Other',
        status: json['status']?.toString() ?? 'Open',
        date: json['date']?.toString() ?? '',
        excerpt: json['excerpt']?.toString() ?? '',
        reportCount: (json['report_count'] as num?)?.toInt() ?? 0,
      );

  _ReportData copyWith({String? status}) => _ReportData(
        id: id,
        postTitle: postTitle,
        author: author,
        type: type,
        status: status ?? this.status,
        date: date,
        excerpt: excerpt,
        reportCount: reportCount,
      );
}

const _kReports = [
  _ReportData(
      id: 'R001',
      postTitle: 'Buy cheap medicines online — click here!',
      author: 'Spam Account #42',
      type: 'Spam',
      status: 'Open',
      date: 'Jun 12, 2024',
      excerpt:
          'Get the best deals on poultry medicines without prescription. Click the link below…',
      reportCount: 5),
  _ReportData(
      id: 'R002',
      postTitle: 'This vaccination method is dangerous and kills chickens',
      author: 'Farmer Alam',
      type: 'Misinformation',
      status: 'Open',
      date: 'Jun 11, 2024',
      excerpt:
          'Do not follow the official vaccination schedule, it will kill your flock within days…',
      reportCount: 3),
  _ReportData(
      id: 'R003',
      postTitle: 'Rival farm workers are thieves',
      author: 'Anonymous User',
      type: 'Harassment',
      status: 'Open',
      date: 'Jun 10, 2024',
      excerpt:
          'Naming specific people and accusing them of stealing. Personal attack post.',
      reportCount: 2),
];

class _UserSummary {
  final String id, name;
  final int postCount, reportCount;
  final bool verified, muted;

  const _UserSummary({
    required this.id,
    required this.name,
    required this.postCount,
    required this.reportCount,
    required this.verified,
    required this.muted,
  });

  factory _UserSummary.fromJson(Map<String, dynamic> json) => _UserSummary(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? '',
        postCount: (json['post_count'] as num?)?.toInt() ??
            (json['posts'] as num?)?.toInt() ??
            0,
        reportCount: (json['report_count'] as num?)?.toInt() ?? 0,
        verified: json['verified'] == true,
        muted: json['muted'] == true,
      );

  _UserSummary copyWith({bool? verified, bool? muted}) => _UserSummary(
        id: id,
        name: name,
        postCount: postCount,
        reportCount: reportCount,
        verified: verified ?? this.verified,
        muted: muted ?? this.muted,
      );
}

const _kUsers = [
  _UserSummary(
      id: 'CU001',
      name: 'Dr. Kamrul Islam',
      postCount: 42,
      reportCount: 0,
      verified: true,
      muted: false),
  _UserSummary(
      id: 'CU002',
      name: 'Farmer Alam',
      postCount: 18,
      reportCount: 3,
      verified: false,
      muted: false),
  _UserSummary(
      id: 'CU003',
      name: 'Spam Account #42',
      postCount: 7,
      reportCount: 5,
      verified: false,
      muted: false),
  _UserSummary(
      id: 'CU004',
      name: 'Sumaiya Research',
      postCount: 31,
      reportCount: 0,
      verified: true,
      muted: false),
];
