import 'package:flutter/material.dart';

import '../../data/models/admin_role.dart';
import '../../data/services/audit_service.dart';
import '../../data/services/admin_api_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/module_activity.dart';
import '../widgets/permission_guard.dart';

class AdminCommunityScreen extends StatefulWidget {
  const AdminCommunityScreen({super.key});

  @override
  State<AdminCommunityScreen> createState() => _AdminCommunityScreenState();
}

class _AdminCommunityScreenState extends State<AdminCommunityScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  List<_Report> _reports = const [];
  List<_Member> _members = const [];
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
    try {
      final data = await Future.wait([
        AdminApiService.instance.list('community-reports'),
        AdminApiService.instance.list('community-users'),
      ]);
      if (!mounted) return;
      setState(() {
        _reports = data[0].map(_Report.fromJson).toList();
        _members = data[1].map(_Member.fromJson).toList();
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  Future<void> _reportAction(_Report report, String action, {String? reason}) async {
    try {
      await AdminApiService.instance.update('community-reports', report.id, {
        'action': action,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      });
      AuditService.instance.log('Community Moderation', action, report.excerpt);
      _snack('Report ${action}d.', action == 'dismiss' ? AColors.grey : AColors.red);
      await _load();
    } catch (e) {
      _snack(e.toString(), AColors.red);
    }
  }

  Future<void> _memberAction(_Member member, Map<String, dynamic> body, String label) async {
    try {
      await AdminApiService.instance.update('community-users', member.id, body);
      AuditService.instance.log('Community Moderation', label, member.name);
      _snack('$label — ${member.name}', AColors.orange);
      await _load();
    } catch (e) {
      _snack(e.toString(), AColors.red);
    }
  }

  Future<String?> _askReason(String title) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Reason (shown to the author)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Confirm')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final open = _reports.where((r) => r.status == 'Open').toList();
    final actioned = _reports
        .where((r) => r.status != 'Open' || r.contentStatus != 'active')
        .toList();

    return AdminScaffold(
      title: 'Community Moderation',
      module: AdminModule.communityModeration,
      appBarActions: const [
        ModuleActivityButton(title: 'Community', modules: ['community-reports', 'community-users']),
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
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: [
                Tab(text: 'Open Reports (${open.length})'),
                Tab(text: 'Actioned (${actioned.length})'),
                Tab(text: 'Members (${_members.length})'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AColors.secondary))
                : _error != null
                    ? _ErrorView(message: _error!, onRetry: _load)
                    : TabBarView(
                        controller: _tabs,
                        children: [
                          _ReportList(
                            reports: open,
                            empty: 'No open reports. The queue is clear.',
                            onRefresh: _load,
                            builder: (r) => _ReportCard(
                              report: r,
                              actions: [
                                PermissionGuard(
                                  module: AdminModule.communityModeration,
                                  permission: AdminPermission.edit,
                                  child: _Btn('Hide', AColors.orange, () async {
                                    final reason = await _askReason('Hide this ${r.targetType}');
                                    if (reason != null) _reportAction(r, 'hide', reason: reason);
                                  }),
                                ),
                                PermissionGuard(
                                  module: AdminModule.communityModeration,
                                  permission: AdminPermission.delete,
                                  child: _Btn('Remove', AColors.red, () async {
                                    final reason = await _askReason('Remove this ${r.targetType}');
                                    if (reason != null) _reportAction(r, 'remove', reason: reason);
                                  }),
                                ),
                                _Btn('Dismiss', AColors.grey, () => _reportAction(r, 'dismiss')),
                              ],
                            ),
                          ),
                          _ReportList(
                            reports: actioned,
                            empty: 'Nothing actioned yet.',
                            onRefresh: _load,
                            builder: (r) => _ReportCard(
                              report: r,
                              actions: [
                                if (r.contentStatus == 'hidden' || r.contentStatus == 'flagged')
                                  PermissionGuard(
                                    module: AdminModule.communityModeration,
                                    permission: AdminPermission.edit,
                                    child: _Btn('Restore', AColors.secondary,
                                        () => _reportAction(r, 'unhide')),
                                  ),
                              ],
                            ),
                          ),
                          _MemberList(
                            members: _members,
                            onRefresh: _load,
                            onMute: (m) async {
                              final reason = await _askReason('Mute ${m.name} from the community');
                              if (reason != null) {
                                _memberAction(m, {'action': 'mute', 'reason': reason}, 'Mute member');
                              }
                            },
                            onUnmute: (m) => _memberAction(m, {'action': 'unmute'}, 'Unmute member'),
                            onVerify: (m) => _memberAction(m, {'verified': true}, 'Grant verified badge'),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

// ── report list / card ───────────────────────────────────────────────────────

class _ReportList extends StatelessWidget {
  const _ReportList({
    required this.reports,
    required this.empty,
    required this.onRefresh,
    required this.builder,
  });

  final List<_Report> reports;
  final String empty;
  final Future<void> Function() onRefresh;
  final Widget Function(_Report) builder;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: reports.isEmpty
          ? ListView(children: [
              const SizedBox(height: 120),
              Center(child: Text(empty, style: const TextStyle(color: AColors.textSecondary, fontSize: 13))),
            ])
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: reports.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => builder(reports[i]),
            ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.actions});
  final _Report report;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (report.contentStatus) {
      'active' => AColors.grey,
      'flagged' => AColors.amber,
      'hidden' => AColors.orange,
      _ => AColors.red,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: aCard(highlight: report.reportCount >= 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            aChip(report.reason, AColors.purple, AColors.purple),
            const SizedBox(width: 6),
            aChip('${report.reportCount} reports', AColors.red, AColors.red, fontSize: 10),
            const SizedBox(width: 6),
            aChip(report.contentStatus, statusColor, statusColor, fontSize: 10),
            const Spacer(),
            Text(report.date, style: const TextStyle(fontSize: 10, color: AColors.grey)),
          ]),
          const SizedBox(height: 8),
          Text(report.postTitle.isEmpty ? '(${report.targetType})' : report.postTitle,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
          Text('by ${report.author}${report.isAnonymous ? ' · anonymous' : ''} · reported by ${report.reporter}',
              style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
          if (report.excerpt.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(report.excerpt,
                style: const TextStyle(fontSize: 12, color: AColors.grey, height: 1.4),
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: actions),
          ],
        ],
      ),
    );
  }
}

// ── members ──────────────────────────────────────────────────────────────────

class _MemberList extends StatelessWidget {
  const _MemberList({
    required this.members,
    required this.onRefresh,
    required this.onMute,
    required this.onUnmute,
    required this.onVerify,
  });

  final List<_Member> members;
  final Future<void> Function() onRefresh;
  final void Function(_Member) onMute;
  final void Function(_Member) onUnmute;
  final void Function(_Member) onVerify;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: members.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final m = members[i];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: aCard(highlight: m.reportsAgainst >= 5),
            child: Row(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AColors.secondary.withValues(alpha: 0.15),
                child: Text(m.name.isEmpty ? '?' : m.name[0],
                    style: const TextStyle(color: AColors.secondary, fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(m.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600, color: AColors.textPrimary)),
                    ),
                    if (m.verified) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified, color: AColors.secondary, size: 14),
                    ],
                    if (m.badge != null) ...[
                      const SizedBox(width: 6),
                      aChip(m.badge!, AColors.blue, AColors.blue, fontSize: 9),
                    ],
                    if (m.muted) ...[
                      const SizedBox(width: 6),
                      aChip('Muted', AColors.orange, AColors.orange, fontSize: 9),
                    ],
                  ]),
                  Text('${m.role} · ${m.posts} posts · ${m.helpful} helpful · ${m.reportsAgainst} reports',
                      style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
                  if (m.muteReason != null && m.muteReason!.isNotEmpty)
                    Text('Mute reason: ${m.muteReason}',
                        style: const TextStyle(fontSize: 10, color: AColors.orange)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (m.muted)
                  _Btn('Unmute', AColors.secondary, () => onUnmute(m))
                else
                  PermissionGuard(
                    module: AdminModule.communityModeration,
                    permission: AdminPermission.suspend,
                    child: _Btn('Mute', AColors.orange, () => onMute(m)),
                  ),
                const SizedBox(height: 4),
                if (!m.verified)
                  PermissionGuard(
                    module: AdminModule.communityModeration,
                    permission: AdminPermission.approve,
                    child: _Btn('Verify', AColors.secondary, () => onVerify(m)),
                  ),
              ]),
            ]),
          );
        },
      ),
    );
  }
}

// ── helpers ──────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off, color: AColors.grey),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      );
}

class _Btn extends StatelessWidget {
  const _Btn(this.label, this.color, this.onTap);
  final String label;
  final Color color;
  final VoidCallback onTap;

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
          child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

// ── models ───────────────────────────────────────────────────────────────────

class _Report {
  const _Report({
    required this.id,
    required this.targetType,
    required this.postTitle,
    required this.excerpt,
    required this.author,
    required this.isAnonymous,
    required this.reporter,
    required this.reason,
    required this.status,
    required this.contentStatus,
    required this.reportCount,
    required this.date,
  });

  final String id, targetType, postTitle, excerpt, author, reporter, reason, status, contentStatus, date;
  final bool isAnonymous;
  final int reportCount;

  factory _Report.fromJson(Map<String, dynamic> j) => _Report(
        id: j['id'].toString(),
        targetType: j['target_type']?.toString() ?? 'post',
        postTitle: j['post_title']?.toString() ?? '',
        excerpt: j['excerpt']?.toString() ?? '',
        author: j['author']?.toString() ?? 'Unknown',
        isAnonymous: j['is_anonymous'] == true,
        reporter: j['reporter']?.toString() ?? '',
        reason: j['reason']?.toString() ?? 'other',
        status: j['status']?.toString() ?? 'Open',
        contentStatus: j['content_status']?.toString() ?? 'active',
        reportCount: (j['report_count'] as num?)?.toInt() ?? 0,
        date: j['date']?.toString() ?? '',
      );
}

class _Member {
  const _Member({
    required this.id,
    required this.name,
    required this.role,
    required this.posts,
    required this.helpful,
    required this.reportsAgainst,
    required this.verified,
    required this.muted,
    this.badge,
    this.muteReason,
  });

  final String id, name, role;
  final int posts, helpful, reportsAgainst;
  final bool verified, muted;
  final String? badge, muteReason;

  factory _Member.fromJson(Map<String, dynamic> j) => _Member(
        id: j['id'].toString(),
        name: j['name']?.toString() ?? '',
        role: j['role']?.toString() ?? 'Farmer',
        posts: (j['posts'] as num?)?.toInt() ?? 0,
        helpful: (j['helpful'] as num?)?.toInt() ?? 0,
        reportsAgainst: (j['reports_against'] as num?)?.toInt() ?? 0,
        verified: j['verified'] == true,
        muted: j['muted'] == true,
        badge: j['badge']?.toString(),
        muteReason: j['mute_reason']?.toString(),
      );
}
