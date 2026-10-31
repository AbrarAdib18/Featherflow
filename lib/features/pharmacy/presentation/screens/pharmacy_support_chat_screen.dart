import 'package:flutter/material.dart';

import '../../../../core/network/realtime_chat_service.dart';
import '../../data/services/pharmacy_chat_service.dart';
import '../pharmacy_theme.dart';

/// The pharmacy side of the private pharmacy<->Pharmacy Admin support
/// conversation (spec §8). Reachable at every account lifecycle stage — the
/// backend endpoints it calls use PharmacyAlwaysOnAuthentication, not the
/// standard active-only gate.
class PharmacySupportChatScreen extends StatefulWidget {
  const PharmacySupportChatScreen({super.key});

  @override
  State<PharmacySupportChatScreen> createState() => _PharmacySupportChatScreenState();
}

class _PharmacySupportChatScreenState extends State<PharmacySupportChatScreen> {
  final _api = PharmacyChatService.instance;
  final _realtime = RealtimeChatService();
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  String? _conversationId;
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _realtime.disconnect();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.getOrCreate();
      _conversationId = data['id']?.toString();
      _messages = (data['messages'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (_conversationId != null) {
        await _api.markRead(_conversationId!);
        _realtime.onMessage = (payload) {
          if (!mounted) return;
          setState(() => _messages = [..._messages, payload]);
          _scrollToBottom();
        };
        _realtime.onError = (_) {}; // REST already sent the message; live push is best-effort.
        await _realtime.connect(_conversationId!);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _conversationId == null || _sending) return;
    setState(() => _sending = true);
    _controller.clear();
    try {
      final message = await _api.sendMessage(_conversationId!, text);
      setState(() => _messages = [..._messages, {...message, 'is_mine': true}]);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        showPharmacyNotice(context, 'Could not send: $e', PhColors.red, Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PhColors.bg,
      appBar: AppBar(
        backgroundColor: PhColors.appBar,
        foregroundColor: Colors.white,
        title: const Text('Contact Pharmacy Admin'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : Column(children: [
                  Expanded(
                    child: _messages.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Send a message to start a conversation with Pharmacy Admin — '
                                'about verification, medicine listings, orders, delivery, '
                                'payments, suspension, or a technical issue.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: PhColors.textSecondary),
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.all(12),
                            itemCount: _messages.length,
                            itemBuilder: (context, i) {
                              final m = _messages[i];
                              final mine = m['is_mine'] == true;
                              return Align(
                                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  constraints: BoxConstraints(
                                      maxWidth: MediaQuery.of(context).size.width * 0.75),
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: mine ? PhColors.secondary : PhColors.surface2,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    (m['content'] ?? '').toString(),
                                    style: TextStyle(
                                        color: mine ? Colors.white : PhColors.textPrimary, fontSize: 14),
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
                            decoration: phInput('Message', Icons.message_outlined),
                            minLines: 1,
                            maxLines: 4,
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: _sending ? null : _send,
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_outlined, size: 40, color: PhColors.red),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: PhColors.textSecondary)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      ),
    );
  }
}
