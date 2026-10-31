import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/auth_service.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/profile_photo_field.dart';
import '../../../community/presentation/screens/community_feed_screen.dart';
import '../../data/services/feed_owner_service.dart';
import 'feed_owner_chat_screen.dart';

/// The Feed Inventory Owner's whole app surface: a restricted profile +
/// inventory summary + a single "Chat with Feed Marketplace Admin" action +
/// Community access + logout. Deliberately NOT the Feed Marketplace Admin
/// sidebar/shell — this role has no admin controls, and every restriction is
/// also enforced server-side (feed_catalogue.owner_permissions.IsFeedOwnerAccount),
/// not just by what this screen chooses to show.
class FeedOwnerHomeScreen extends StatefulWidget {
  const FeedOwnerHomeScreen({super.key});

  @override
  State<FeedOwnerHomeScreen> createState() => _FeedOwnerHomeScreenState();
}

class _FeedOwnerHomeScreenState extends State<FeedOwnerHomeScreen> {
  final _api = FeedOwnerService.instance;
  Map<String, dynamic>? _profile;
  int _unread = 0;
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
      final profile = await _api.profile();
      var unread = 0;
      try {
        final chat = await _api.fetchChat();
        if (chat['exists'] == true) unread = (chat['unread_count'] as num?)?.toInt() ?? 0;
      } catch (_) {
        // Chat is secondary to the profile load — never block the home
        // screen on it.
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _unread = unread;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await AuthService.instance.clearSession();
    if (mounted) context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feed Inventory Owner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _logout,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.cloud_off_outlined, size: 40),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _load, child: const Text('Retry')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _profileCard(context),
                      const SizedBox(height: 16),
                      _inventoryCard(context),
                      const SizedBox(height: 16),
                      _chatCard(context),
                      const SizedBox(height: 16),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.forum_outlined),
                          title: const Text('Community'),
                          subtitle: const Text('Share feed availability, prices and updates'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const CommunityFeedScreen())),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _profileCard(BuildContext context) {
    final p = _profile ?? const {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          ListenableBuilder(
            listenable: AuthService.instance,
            builder: (_, __) => ProfilePhotoField(
              radius: 28,
              showLabel: false,
              editable: true,
              currentUrl: (p['profile_photo_url'] ?? '').toString(),
              fallbackIcon: Icons.inventory_2_outlined,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((p['full_name'] ?? '').toString(),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Chip(
                label: Text((p['role_label'] ?? 'Feed Inventory Owner').toString()),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(height: 6),
              Text((p['email'] ?? '').toString(), style: Theme.of(context).textTheme.bodySmall),
              if ((p['phone'] ?? '').toString().isNotEmpty)
                Text((p['phone']).toString(), style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _inventoryCard(BuildContext context) {
    final p = _profile ?? const {};
    final categories = (p['assigned_categories'] as List? ?? const []).join(', ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Inventory context', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _row(context, 'Business name', (p['business_name'] ?? '—').toString()),
          _row(context, 'Inventory location', (p['inventory_location'] ?? '—').toString()),
          _row(context, 'Assigned categories', categories.isEmpty ? '—' : categories),
          _row(context, 'Status', (p['status'] ?? '—').toString()),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 150, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
      ]),
    );
  }

  Widget _chatCard(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.support_agent_outlined),
        title: const Text('Chat with Feed Marketplace Admin'),
        subtitle: const Text('Stock, orders, and delivery questions'),
        trailing: _unread > 0
            ? CircleAvatar(
                radius: 12,
                backgroundColor: Theme.of(context).colorScheme.error,
                child: Text('$_unread',
                    style: const TextStyle(color: Colors.white, fontSize: 11)),
              )
            : const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const FeedOwnerChatScreen()));
          _load();
        },
      ),
    );
  }
}
