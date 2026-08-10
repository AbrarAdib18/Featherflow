import 'package:flutter/material.dart';
import '../../data/models/doctor_models.dart';
import '../../data/services/doctor_session.dart';
import '../doctor_theme.dart';

class DoctorMessengerScreen extends StatelessWidget {
  const DoctorMessengerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DoctorSession.instance,
      builder: (context, _) {
        final threads = DoctorSession.instance.chatThreads.toList()
          ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));

        return Scaffold(
          backgroundColor: VetColors.bg,
          appBar: AppBar(
            backgroundColor: VetColors.appBar,
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                const Text(
                  'Messages',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                if (DoctorSession.instance.unreadMessages > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: VetColors.emergency,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${DoctorSession.instance.unreadMessages}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          body: threads.isEmpty
              ? const _EmptyState()
              : ListView.separated(
                  itemCount: threads.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    color: VetColors.divider,
                    indent: 72,
                  ),
                  itemBuilder: (_, i) => _ThreadTile(
                    thread: threads[i],
                    onTap: () => _openChat(context, threads[i]),
                  ),
                ),
        );
      },
    );
  }

  void _openChat(BuildContext context, ChatThread thread) {
    DoctorSession.instance.markThreadRead(thread.id);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ChatScreen(threadId: thread.id),
      ),
    );
  }
}

// ── Thread Tile ───────────────────────────────────────────────────────────────

class _ThreadTile extends StatelessWidget {
  final ChatThread thread;
  final VoidCallback onTap;
  const _ThreadTile({required this.thread, required this.onTap});

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = thread.unreadCount > 0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: hasUnread
                      ? VetColors.secondary.withValues(alpha: 0.15)
                      : VetColors.surface2,
                  child: Text(
                    thread.farmerName.isNotEmpty ? thread.farmerName[0] : 'F',
                    style: TextStyle(
                      color: hasUnread ? VetColors.secondary : VetColors.grey,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                if (hasUnread)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: VetColors.secondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          thread.farmerName,
                          style: TextStyle(
                            color: VetColors.textPrimary,
                            fontSize: 14,
                            fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _timeAgo(thread.lastMessageAt),
                        style: TextStyle(
                          color: hasUnread ? VetColors.secondary : VetColors.grey,
                          fontSize: 11,
                          fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    thread.farmName,
                    style: const TextStyle(color: VetColors.textSecondary, fontSize: 11),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          thread.lastMessage ?? '',
                          style: TextStyle(
                            color: hasUnread ? VetColors.textPrimary : VetColors.grey,
                            fontSize: 12,
                            fontWeight: hasUnread ? FontWeight.w500 : FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: VetColors.secondary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${thread.unreadCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Chat Screen ───────────────────────────────────────────────────────────────

class _ChatScreen extends StatefulWidget {
  final String threadId;
  const _ChatScreen({required this.threadId});

  @override
  State<_ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<_ChatScreen> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  static const _quickReplies = [
    'Please send photos of affected birds.',
    'Follow the dosage instructions shared.',
    'Isolate the sick birds immediately.',
    'I will review and respond shortly.',
    'Schedule a follow-up appointment.',
    'Contact me if mortality increases.',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    DoctorSession.instance.sendMessage(
      widget.threadId,
      ChatMessage(
        id: 'MSG-${DateTime.now().millisecondsSinceEpoch}',
        fromDoctor: true,
        content: text,
        type: MessageType.text,
        sentAt: DateTime.now(),
      ),
    );
    _ctrl.clear();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendQuickReply(String text) {
    DoctorSession.instance.sendMessage(
      widget.threadId,
      ChatMessage(
        id: 'MSG-${DateTime.now().millisecondsSinceEpoch}',
        fromDoctor: true,
        content: text,
        type: MessageType.text,
        sentAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DoctorSession.instance,
      builder: (context, _) {
        final threads = DoctorSession.instance.chatThreads;
        final matchingThreads = threads.where((t) => t.id == widget.threadId).toList();
        if (matchingThreads.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('Conversation not found.')),
          );
        }
        final thread = matchingThreads.first;

        return Scaffold(
          backgroundColor: VetColors.bg,
          appBar: AppBar(
            backgroundColor: VetColors.appBar,
            foregroundColor: Colors.white,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  thread.farmerName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                Text(
                  thread.farmName,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.videocam_outlined, color: Colors.white),
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Video call — add a WebRTC package to enable.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                ),
                tooltip: 'Video Call',
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  itemCount: thread.messages.length,
                  itemBuilder: (_, i) => _MessageBubble(message: thread.messages[i]),
                ),
              ),
              // Quick replies
              if (thread.messages.isNotEmpty &&
                  !thread.messages.last.fromDoctor)
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _quickReplies.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => _sendQuickReply(_quickReplies[i]),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: VetColors.secondary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: VetColors.secondary.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          _quickReplies[i],
                          style: const TextStyle(
                            color: VetColors.secondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              // Input bar
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                decoration: const BoxDecoration(
                  color: VetColors.bg,
                  border: Border(top: BorderSide(color: VetColors.divider)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.attach_file, color: VetColors.grey, size: 22),
                      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('File sharing — connect your backend to enable.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        maxLines: 4,
                        minLines: 1,
                        style: const TextStyle(color: VetColors.textPrimary, fontSize: 14),
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'Type a message…',
                          hintStyle: const TextStyle(color: VetColors.grey, fontSize: 13),
                          filled: true,
                          fillColor: VetColors.surface2,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _send,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: VetColors.secondary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Message Bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  String _time(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final isDoctor = message.fromDoctor;
    final isImage = message.type == MessageType.image;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isDoctor ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isDoctor) ...[
            const CircleAvatar(
              radius: 14,
              backgroundColor: VetColors.surface2,
              child: Icon(Icons.person, size: 16, color: VetColors.grey),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isDoctor ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72,
                  ),
                  padding: isImage
                      ? EdgeInsets.zero
                      : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDoctor
                        ? VetColors.primary
                        : VetColors.surface2,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isDoctor ? 16 : 4),
                      bottomRight: Radius.circular(isDoctor ? 4 : 16),
                    ),
                  ),
                  child: isImage
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            height: 120,
                            width: 200,
                            color: VetColors.surface2,
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.image_outlined, color: VetColors.grey, size: 32),
                                  SizedBox(height: 4),
                                  Text('Image', style: TextStyle(color: VetColors.grey, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        )
                      : Text(
                          message.content,
                          style: TextStyle(
                            color: isDoctor ? Colors.white : VetColors.textPrimary,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                ),
                const SizedBox(height: 3),
                Text(
                  _time(message.sentAt),
                  style: const TextStyle(color: VetColors.grey, fontSize: 10),
                ),
              ],
            ),
          ),
          if (isDoctor) const SizedBox(width: 6),
        ],
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 52,
            color: VetColors.grey.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          const Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: VetColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Messages from farmers will appear here.',
            style: TextStyle(fontSize: 13, color: VetColors.grey),
          ),
        ],
      ),
    );
  }
}
