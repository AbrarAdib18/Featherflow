import 'package:flutter/material.dart';

import '../../data/services/admin_api_service.dart';

/// Feed Marketplace Admin's team inbox for every Feed Inventory Owner
/// conversation (spec §25) — list + open/resolve/reopen. Mirrors the
/// pharmacy chat inbox's data shape (admin_api_service.dart's
/// feedChats/feedChatDetail/replyFeedChat/setFeedChatStatus), gated
/// server-side by can_perform_action(user, 'feed-orders', ...).
class AdminFeedChatsScreen extends StatefulWidget {
  const AdminFeedChatsScreen({super.key});

  @override
  State<AdminFeedChatsScreen> createState() => _AdminFeedChatsScreenState();
}

class _AdminFeedChatsScreenState extends State<AdminFeedChatsScreen> {
  final _api = AdminApiService.instance;
  List<Map<String, dynamic>> _rows = [];
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
      final rows = await _api.feedChats();
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feed Owner Chats'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
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
              : _rows.isEmpty
                  ? const Center(child: Text('No feed owner conversations yet.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final row = _rows[i];
                          final unread = (row['unread_count'] as num?)?.toInt() ?? 0;
                          return ListTile(
                            title: Text(row['owner_name']?.toString() ?? 'Feed owner'),
                            subtitle: Text(
                              (row['last_message'] ?? '').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Column(mainAxisSize: MainAxisSize.min, children: [
                              Chip(
                                label: Text(row['status']?.toString() ?? 'open'),
                                visualDensity: VisualDensity.compact,
                              ),
                              if (unread > 0)
                                Text('$unread unread',
                                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
                            ]),
                            onTap: () async {
                              await Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => _AdminFeedChatDetailScreen(id: row['id'].toString())));
                              _load();
                            },
                          );
                        },
                      ),
                    ),
    );
  }
}

class _AdminFeedChatDetailScreen extends StatefulWidget {
  const _AdminFeedChatDetailScreen({required this.id});
  final String id;

  @override
  State<_AdminFeedChatDetailScreen> createState() => _AdminFeedChatDetailScreenState();
}

class _AdminFeedChatDetailScreenState extends State<_AdminFeedChatDetailScreen> {
  final _api = AdminApiService.instance;
  final _controller = TextEditingController();
  Map<String, dynamic>? _detail;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _api.feedChatDetail(widget.id);
      if (mounted) setState(() => _detail = detail);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reply() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _api.replyFeedChat(widget.id, text);
      _controller.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _setStatus(String status) async {
    try {
      await _api.setFeedChatStatus(widget.id, status);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update status: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _detail?['status']?.toString() ?? 'open';
    final messages = (_detail?['messages'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_detail?['owner_name']?.toString() ?? 'Conversation'),
        actions: [
          if (status == 'resolved')
            TextButton(onPressed: () => _setStatus('reopened'), child: const Text('Reopen'))
          else
            TextButton(onPressed: () => _setStatus('resolved'), child: const Text('Resolve')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(children: [
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: messages.length,
                      itemBuilder: (context, i) {
                        final m = messages[i];
                        final fromOwner = m['from_owner'] == true;
                        return Align(
                          alignment: fromOwner ? Alignment.centerLeft : Alignment.centerRight,
                          child: Container(
                            constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.75),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: fromOwner
                                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                                  : Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              (m['content'] ?? '').toString(),
                              style: TextStyle(color: fromOwner ? null : Colors.white),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            decoration: const InputDecoration(
                                labelText: 'Reply', border: OutlineInputBorder()),
                            minLines: 1,
                            maxLines: 4,
                            onSubmitted: (_) => _reply(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: _sending ? null : _reply,
                          icon: _sending
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send),
                        ),
                      ]),
                    ),
                  ),
                ]),
    );
  }
}
