import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/theme/theme.dart';

import '../../data/community_api_service.dart';
import '../widgets/community_widgets.dart';

class CommunityNotificationsScreen extends StatefulWidget {
  const CommunityNotificationsScreen({super.key});

  @override
  State<CommunityNotificationsScreen> createState() => _CommunityNotificationsScreenState();
}

class _CommunityNotificationsScreenState extends State<CommunityNotificationsScreen> {
  final _api = CommunityApiService.instance;
  List<Map<String, dynamic>> _rows = const [];
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.notifications();
      final rows = List<Map<String, dynamic>>.from(
          (data['notifications'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
      if (mounted) {
        setState(() {
          _rows = rows;
          _loaded = true;
          _error = null;
        });
      }
      await _api.markNotificationsRead();
    } on CommunityApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F7),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Community activity'),
      ),
      body: !_loaded
          ? (_error != null
              ? CommunityStateView(icon: Icons.error_outline, title: 'Could not load notifications', subtitle: _error, onRetry: _load)
              : const Center(child: CircularProgressIndicator()))
          : _rows.isEmpty
              ? const CommunityStateView(icon: Icons.notifications_none, title: 'No community activity yet')
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final n = _rows[i];
                      final postId = n['post_id']?.toString();
                      return ListTile(
                        tileColor: n['is_read'] == true ? null : AppColors.secondary.withValues(alpha: 0.06),
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFEAF7F2),
                          child: Icon(Icons.forum_outlined, size: 18, color: AppColors.secondary),
                        ),
                        title: Text(n['title']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        subtitle: Text('${n['message'] ?? ''}\n${n['time'] ?? ''}', style: const TextStyle(fontSize: 12)),
                        isThreeLine: true,
                        onTap: postId == null ? null : () => context.push('/community/post/$postId'),
                      );
                    },
                  ),
                ),
    );
  }
}
