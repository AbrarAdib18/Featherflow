import 'package:flutter/material.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/audit_service.dart';
import '../../data/services/admin_api_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';
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

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _articles = [];
    _loadArticles();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
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
                Tab(text: 'All Content'),
                Tab(text: 'Pending Review'),
                Tab(text: 'Featured'),
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

const _kArticles = [
  _ArticleData(
      id: 'A001',
      title: 'Combating Newcastle Disease in Commercial Broilers',
      author: 'Dr. Sumaiya Islam · BRAC University',
      type: 'Research',
      status: 'Published',
      date: 'Jun 1, 2024',
      summary:
          'A comprehensive study on vaccination protocols and biosecurity measures for Newcastle disease management.',
      featured: true),
  _ArticleData(
      id: 'A002',
      title: 'Government Announces New Poultry Subsidy Program',
      author: 'Featherflow Editorial Team',
      type: 'News',
      status: 'Pending',
      date: 'Jun 10, 2024',
      summary:
          'The Ministry of Agriculture has announced a ৳50 crore subsidy package for small-scale poultry farmers.'),
  _ArticleData(
      id: 'A003',
      title: 'AI-Based Feed Optimization: A Field Trial',
      author: 'Dr. Karim Research Group',
      type: 'Innovation',
      status: 'Published',
      date: 'May 22, 2024',
      summary:
          'A field trial of machine learning models for optimizing feed ratios showed 12% improvement in FCR.'),
  _ArticleData(
      id: 'A004',
      title: 'Biosecurity Checklist for Layer Farms',
      author: 'Dr. Shahid Hossain',
      type: 'Research',
      status: 'Pending',
      date: 'Jun 8, 2024',
      summary:
          'A practical guide covering entry protocols, sanitation, and flock health monitoring for layer operations.'),
];
