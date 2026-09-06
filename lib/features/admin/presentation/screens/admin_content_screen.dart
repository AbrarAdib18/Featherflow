import 'package:flutter/material.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/audit_service.dart';
import '../../data/services/admin_api_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/module_activity.dart';
import '../widgets/permission_guard.dart';
import '../widgets/admin_dialogs.dart';

class AdminContentScreen extends StatefulWidget {
  const AdminContentScreen({super.key});

  @override
  State<AdminContentScreen> createState() => _AdminContentScreenState();
}

class _AdminContentScreenState extends State<AdminContentScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late List<_ArticleData> _articles;
  bool _loading = true;
  List<Map<String, dynamic>> _applications = [];
  bool _loadingApplications = true;
  List<Map<String, dynamic>> _reports = [];
  bool _loadingReports = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _articles = [];
    _loadArticles();
    _loadApplications();
    _loadReports();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadApplications() async {
    try {
      final data = await AdminApiService.instance.list('profile-change-applications');
      if (!mounted) return;
      setState(() {
        _applications = data;
        _loadingApplications = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingApplications = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString()), backgroundColor: AColors.red));
    }
  }

  Future<void> _approveApplication(String id) async {
    try {
      final updated = await AdminApiService.instance
          .update('profile-change-applications', id, {'action': 'approve'});
      if (!mounted) return;
      setState(() {
        final i = _applications.indexWhere((a) => a['id'] == id);
        if (i >= 0) _applications[i] = updated;
      });
      AuditService.instance.log('Research & Articles', 'Approve profile change', id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString()), backgroundColor: AColors.red));
    }
  }

  Future<void> _rejectApplication(String id) async {
    final values = await showAdminRecordEditor(context,
        title: 'Reject Application', fields: {'Review note': ''});
    if (values == null) return;
    final note = values['Review note']?.trim() ?? '';
    if (note.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('A review note is required to reject an application.'),
          backgroundColor: AColors.red));
      return;
    }
    try {
      final updated = await AdminApiService.instance.update(
          'profile-change-applications', id, {'action': 'reject', 'review_note': note});
      if (!mounted) return;
      setState(() {
        final i = _applications.indexWhere((a) => a['id'] == id);
        if (i >= 0) _applications[i] = updated;
      });
      AuditService.instance.log('Research & Articles', 'Reject profile change', id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString()), backgroundColor: AColors.red));
    }
  }

  Future<void> _loadReports() async {
    try {
      final data = await AdminApiService.instance.list('content-reports');
      if (!mounted) return;
      setState(() {
        _reports = data;
        _loadingReports = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingReports = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString()), backgroundColor: AColors.red));
    }
  }

  Future<void> _actOnReport(String id, String action) async {
    try {
      final updated = await AdminApiService.instance
          .update('content-reports', id, {'action': action});
      if (!mounted) return;
      setState(() {
        final i = _reports.indexWhere((r) => r['id'] == id);
        if (i >= 0) _reports[i] = updated;
      });
      AuditService.instance.log('Research & Articles', 'Content report $action', id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString()), backgroundColor: AColors.red));
    }
  }

  Future<void> _composeTeamUpdate() async {
    final values = await showAdminRecordEditor(context, title: 'Compose Team Update', fields: {
      'Title': '',
      'Summary': '',
      'Body': '',
    });
    if (values == null) return;
    final title = values['Title']?.trim() ?? '';
    final body = values['Body']?.trim() ?? '';
    if (title.isEmpty || body.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Title and body are required.'), backgroundColor: AColors.red));
      return;
    }
    try {
      final result = await AdminApiService.instance.create('team-updates', {
        'title': title,
        'summary': values['Summary']?.trim() ?? '',
        'body': body,
        'is_featured': true,
      });
      if (!mounted) return;
      setState(() => _articles.insert(0, _ArticleData.fromJson(result)));
      AuditService.instance.log('Research & Articles', 'Post team update', title);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Team update published.'), backgroundColor: AColors.green));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString()), backgroundColor: AColors.red));
    }
  }

  Future<void> _loadArticles() async {
    try {
      final data = await AdminApiService.instance.list('articles');
      if (!mounted) return;
      setState(() {
        _articles = data.map(_ArticleData.fromJson).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString()), backgroundColor: AColors.red));
    }
  }

  Future<_ArticleData> _update(String id, Map<String, dynamic> values) async =>
      _ArticleData.fromJson(
          await AdminApiService.instance.update('articles', id, values));

  Future<void> _approve(String id) async {
    final art = _articles.firstWhere((a) => a.id == id);
    final updated = await _update(id, {'status': 'Published'});
    if (!mounted) return;
    setState(() {
      final i = _articles.indexOf(art);
      _articles[i] = updated;
    });
    AuditService.instance.log('Research & Articles', 'Approve', art.title);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Article published'),
        backgroundColor: AColors.green,
        duration: Duration(seconds: 2)));
  }

  Future<void> _hide(String id) async {
    final art = _articles.firstWhere((a) => a.id == id);
    final updated = await _update(id, {'status': 'Hidden'});
    if (!mounted) return;
    setState(() {
      final i = _articles.indexOf(art);
      _articles[i] = updated;
    });
    AuditService.instance.log('Research & Articles', 'Hide', art.title);
  }

  Future<void> _remove(String id) async {
    final art = _articles.firstWhere((a) => a.id == id);
    final updated = await _update(id, {'status': 'Removed'});
    if (!mounted) return;
    setState(() {
      final i = _articles.indexOf(art);
      _articles[i] = updated;
    });
    AuditService.instance.log('Research & Articles', 'Remove', art.title);
  }

  Future<void> _feature(String id) async {
    final art = _articles.firstWhere((a) => a.id == id);
    final updated = await _update(id, {'featured': !art.featured});
    if (!mounted) return;
    setState(() {
      final i = _articles.indexOf(art);
      _articles[i] = updated;
    });
  }

  Future<void> _edit(_ArticleData article) async {
    final values =
        await showAdminRecordEditor(context, title: 'Edit Article', fields: {
      'Title': article.title,
      'Author': article.author,
      'Type': article.type,
      'Summary': article.summary,
      'Date': article.date,
    });
    if (values == null) return;
    final updated = await _update(article.id, {
      'title': values['Title'],
      'author': values['Author'],
      'type': values['Type'],
      'summary': values['Summary'],
      'date': values['Date'],
    });
    if (!mounted) return;
    setState(() => _articles[_articles.indexOf(article)] = updated);
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Research & Articles',
      module: AdminModule.researchArticles,
      appBarActions: [
        const ModuleActivityButton(
            title: 'Content', modules: ['articles', 'researchers', 'content-reports']),
        PermissionGuard(
          module: AdminModule.researchArticles,
          permission: AdminPermission.create,
          child: TextButton.icon(
            onPressed: _composeTeamUpdate,
            icon: const Icon(Icons.campaign_outlined, color: Colors.white, size: 18),
            label: const Text('Post Update', style: TextStyle(color: Colors.white)),
          ),
        ),
      ],
      child: Column(
        children: [
          Container(
            color: AColors.appBar,
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              indicatorColor: AColors.secondary,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'All Content'),
                Tab(text: 'Pending Review'),
                Tab(text: 'Featured'),
                Tab(text: 'Team Updates'),
                Tab(text: 'Profile Applications'),
                Tab(text: 'Content Reports'),
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
                      _ArticleList(
                          articles: _articles,
                          onApprove: _approve,
                          onHide: _hide,
                          onRemove: _remove,
                          onEdit: _edit,
                          onFeature: _feature),
                      _ArticleList(
                          articles: _articles
                              .where((a) => a.status == 'Pending')
                              .toList(),
                          onApprove: _approve,
                          onHide: _hide,
                          onRemove: _remove,
                          onEdit: _edit,
                          onFeature: _feature),
                      _ArticleList(
                          articles: _articles.where((a) => a.featured).toList(),
                          onApprove: _approve,
                          onHide: _hide,
                          onRemove: _remove,
                          onEdit: _edit,
                          onFeature: _feature),
                      _ArticleList(
                          articles:
                              _articles.where((a) => a.type == 'Team Update').toList(),
                          onApprove: _approve,
                          onHide: _hide,
                          onRemove: _remove,
                          onEdit: _edit,
                          onFeature: _feature),
                      _loadingApplications
                          ? const Center(
                              child: CircularProgressIndicator(color: AColors.secondary))
                          : _ApplicationsList(
                              applications: _applications,
                              onApprove: _approveApplication,
                              onReject: _rejectApplication,
                            ),
                      _loadingReports
                          ? const Center(
                              child: CircularProgressIndicator(color: AColors.secondary))
                          : _ReportsList(reports: _reports, onAct: _actOnReport),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Article list ──────────────────────────────────────────────────────────────

class _ArticleList extends StatelessWidget {
  final List<_ArticleData> articles;
  final void Function(String) onApprove;
  final void Function(String) onHide;
  final void Function(String) onRemove;
  final void Function(_ArticleData) onEdit;
  final void Function(String) onFeature;

  const _ArticleList({
    required this.articles,
    required this.onApprove,
    required this.onHide,
    required this.onRemove,
    required this.onEdit,
    required this.onFeature,
  });

  @override
  Widget build(BuildContext context) {
    if (articles.isEmpty) {
      return const Center(
          child: Text('No articles here.',
              style: TextStyle(color: AColors.textSecondary, fontSize: 13)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: articles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _ArticleCard(
        article: articles[i],
        onApprove: onApprove,
        onHide: onHide,
        onRemove: onRemove,
        onEdit: onEdit,
        onFeature: onFeature,
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final _ArticleData article;
  final void Function(String) onApprove;
  final void Function(String) onHide;
  final void Function(String) onRemove;
  final void Function(_ArticleData) onEdit;
  final void Function(String) onFeature;

  const _ArticleCard({
    required this.article,
    required this.onApprove,
    required this.onHide,
    required this.onRemove,
    required this.onEdit,
    required this.onFeature,
  });

  Color get _typeColor {
    switch (article.type) {
      case 'Research':
        return AColors.purple;
      case 'News':
        return AColors.blue;
      default:
        return AColors.secondary;
    }
  }

  Color get _statusColor {
    switch (article.status) {
      case 'Published':
        return AColors.green;
      case 'Pending':
        return AColors.amber;
      case 'Hidden':
        return AColors.grey;
      default:
        return AColors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: aCard(highlight: article.status == 'Pending'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              aChip(article.type, _typeColor, _typeColor),
              const SizedBox(width: 6),
              aChip(article.status, _statusColor, _statusColor),
              if (article.featured) ...[
                const SizedBox(width: 6),
                aChip('Featured', AColors.amber, AColors.amber),
              ],
              const Spacer(),
              Text(article.date,
                  style: const TextStyle(fontSize: 10, color: AColors.grey)),
            ],
          ),
          const SizedBox(height: 8),
          Text(article.title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AColors.textPrimary)),
          const SizedBox(height: 4),
          Text(article.author,
              style:
                  const TextStyle(fontSize: 12, color: AColors.textSecondary)),
          const SizedBox(height: 4),
          Text(article.summary,
              style: const TextStyle(fontSize: 12, color: AColors.grey),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (article.status == 'Pending')
                PermissionGuard(
                  module: AdminModule.researchArticles,
                  permission: AdminPermission.approve,
                  child: _Chip(
                      'Approve', AColors.green, () => onApprove(article.id)),
                ),
              PermissionGuard(
                module: AdminModule.researchArticles,
                permission: AdminPermission.edit,
                child: _Chip('Edit', AColors.blue, () => onEdit(article)),
              ),
              PermissionGuard(
                module: AdminModule.researchArticles,
                permission: AdminPermission.edit,
                child: _Chip(article.featured ? 'Unfeature' : 'Feature',
                    AColors.amber, () => onFeature(article.id)),
              ),
              if (article.status == 'Published')
                PermissionGuard(
                  module: AdminModule.researchArticles,
                  permission: AdminPermission.edit,
                  child: _Chip('Hide', AColors.grey, () => onHide(article.id)),
                ),
              PermissionGuard(
                module: AdminModule.researchArticles,
                permission: AdminPermission.delete,
                child: _Chip('Remove', AColors.red, () => onRemove(article.id)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Profile change applications ────────────────────────────────────────────────

class _ApplicationsList extends StatelessWidget {
  final List<Map<String, dynamic>> applications;
  final void Function(String) onApprove;
  final void Function(String) onReject;

  const _ApplicationsList({
    required this.applications,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    if (applications.isEmpty) {
      return const Center(
          child: Text('No profile change applications.',
              style: TextStyle(color: AColors.textSecondary, fontSize: 13)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: applications.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final app = applications[i];
        final status = app['status']?.toString() ?? 'pending';
        final statusColor = switch (status) {
          'approved' => AColors.green,
          'rejected' => AColors.red,
          _ => AColors.amber,
        };
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: aCard(highlight: status == 'pending'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  aChip(status.toUpperCase(), statusColor, statusColor),
                  const Spacer(),
                  Text(app['created_at']?.toString().split('T').first ?? '',
                      style: const TextStyle(fontSize: 10, color: AColors.grey)),
                ],
              ),
              const SizedBox(height: 8),
              Text(app['researcher_name']?.toString() ?? '',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
              const SizedBox(height: 4),
              Text('Field: ${app['field_name']}',
                  style: const TextStyle(fontSize: 12, color: AColors.textSecondary)),
              Text('Requested value: ${app['new_value']}',
                  style: const TextStyle(fontSize: 12, color: AColors.textSecondary)),
              const SizedBox(height: 4),
              Text('Reason: ${app['reason']}',
                  style: const TextStyle(fontSize: 12, color: AColors.grey)),
              if ((app['review_note'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Admin note: ${app['review_note']}',
                    style: const TextStyle(fontSize: 12, color: AColors.grey)),
              ],
              if (status == 'pending') ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    PermissionGuard(
                      module: AdminModule.researchArticles,
                      permission: AdminPermission.approve,
                      child: _Chip('Approve', AColors.green, () => onApprove(app['id'].toString())),
                    ),
                    PermissionGuard(
                      module: AdminModule.researchArticles,
                      permission: AdminPermission.edit,
                      child: _Chip('Reject', AColors.red, () => onReject(app['id'].toString())),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ── Content reports ─────────────────────────────────────────────────────────

class _ReportsList extends StatelessWidget {
  final List<Map<String, dynamic>> reports;
  final void Function(String id, String action) onAct;

  const _ReportsList({required this.reports, required this.onAct});

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return const Center(
          child: Text('No content reports.',
              style: TextStyle(color: AColors.textSecondary, fontSize: 13)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: reports.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final report = reports[i];
        final status = report['status']?.toString() ?? 'pending';
        final statusColor = switch (status) {
          'resolved' => AColors.green,
          'reviewed' => AColors.grey,
          _ => AColors.amber,
        };
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: aCard(highlight: status == 'pending'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  aChip(status.toUpperCase(), statusColor, statusColor),
                  const Spacer(),
                  Text(report['created_at']?.toString().split('T').first ?? '',
                      style: const TextStyle(fontSize: 10, color: AColors.grey)),
                ],
              ),
              const SizedBox(height: 8),
              Text(report['article_title']?.toString() ?? 'Content #${report['target_id']}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
              const SizedBox(height: 4),
              Text('Reported by ${report['reporter']}',
                  style: const TextStyle(fontSize: 12, color: AColors.textSecondary)),
              const SizedBox(height: 4),
              Text('Reason: ${report['reason']}',
                  style: const TextStyle(fontSize: 12, color: AColors.grey)),
              if (status == 'pending') ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    PermissionGuard(
                      module: AdminModule.researchArticles,
                      permission: AdminPermission.approve,
                      child: _Chip('Resolve', AColors.green,
                          () => onAct(report['id'].toString(), 'resolve')),
                    ),
                    PermissionGuard(
                      module: AdminModule.researchArticles,
                      permission: AdminPermission.edit,
                      child: _Chip('Dismiss', AColors.grey,
                          () => onAct(report['id'].toString(), 'dismiss')),
                    ),
                  ],
                ),
              ],
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

class _ArticleData {
  final String id, title, author, type, status, date, summary;
  final bool featured;

  const _ArticleData({
    required this.id,
    required this.title,
    required this.author,
    required this.type,
    required this.status,
    required this.date,
    required this.summary,
    this.featured = false,
  });

  factory _ArticleData.fromJson(Map<String, dynamic> json) => _ArticleData(
        id: json['id'].toString(),
        title: json['title']?.toString() ?? '',
        author: json['author']?.toString() ?? '',
        type: json['type']?.toString() ?? 'Article',
        status: json['status']?.toString() ?? 'Pending',
        date: json['date']?.toString() ?? '',
        summary: json['summary']?.toString() ?? '',
        featured: json['featured'] == true,
      );

  _ArticleData copyWith({String? status, bool? featured}) => _ArticleData(
        id: id,
        title: title,
        author: author,
        type: type,
        status: status ?? this.status,
        date: date,
        summary: summary,
        featured: featured ?? this.featured,
      );
}
