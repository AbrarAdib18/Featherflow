import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/auth_service.dart';
import '../../../core/theme/theme.dart';
import '../data/chatbot_service.dart';

/// SharedPreferences key (browser localStorage on web) for the bubble position.
const chatbotPositionPrefsKey = 'featherflow_chatbot_bubble_position';

/// Floating, draggable "Poultry & Featherflow assistant". Installed once from
/// `MaterialApp.router`'s `builder`, so it sits above every route. It renders
/// only while a session exists, i.e. never on splash/login/sign-up.
class ChatbotOverlay extends StatefulWidget {
  const ChatbotOverlay({super.key, required this.child});
  final Widget child;

  @override
  State<ChatbotOverlay> createState() => _ChatbotOverlayState();
}

class _ChatbotOverlayState extends State<ChatbotOverlay> {
  late final OverlayEntry _entry =
      OverlayEntry(builder: (_) => const _ChatLayer());

  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_onAuth);
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    if (mounted) setState(() {});
  }

  bool get _signedIn {
    final s = AuthService.instance.currentSession;
    return s != null && s.accessToken.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        Positioned.fill(child: widget.child),
        // A private Overlay (not Positioned.fill of a plain Stack) because the
        // router's Navigator Overlay is *below* this widget, and text
        // selection / context menus in the chat field need an Overlay ancestor.
        // The Overlay only hit-tests the bubble/panel, so the page underneath
        // keeps receiving taps and scrolls everywhere else.
        if (_signedIn)
          Positioned.fill(
            child: Overlay(initialEntries: [_entry]),
          ),
      ],
    );
  }
}

class _Msg {
  _Msg(this.text, {required this.fromUser, this.refusal = false});
  final String text;
  final bool fromUser;
  final bool refusal;
}

class _ChatLayer extends StatefulWidget {
  const _ChatLayer();

  @override
  State<_ChatLayer> createState() => _ChatLayerState();
}

class _ChatLayerState extends State<_ChatLayer> {
  static const double _bubbleSize = 56;
  static const double _edge = 8;
  static const double _defaultRightGap = 12;
  static const double _defaultBottomGap = 96; // clears bottom navigation bars

  final _bubbleFocus = FocusNode(debugLabel: 'chatbot-bubble');
  final _inputFocus = FocusNode(debugLabel: 'chatbot-input');
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Msg>[];

  /// Bubble position as fractions (0..1) of the movable range, so it survives
  /// window resizes and rotation. Null = default (right edge, near bottom).
  Offset? _frac;
  bool _dragging = false;
  bool _open = false;
  bool _sending = false;
  ChatbotException? _error;
  String? _failedMessage;

  @override
  void initState() {
    super.initState();
    _restorePosition();
  }

  @override
  void dispose() {
    _bubbleFocus.dispose();
    _inputFocus.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── position persistence ───────────────────────────────────────────────

  Future<void> _restorePosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(chatbotPositionPrefsKey);
      if (raw == null || raw.length != 2) return;
      final dx = double.tryParse(raw[0]);
      final dy = double.tryParse(raw[1]);
      if (dx == null || dy == null || !dx.isFinite || !dy.isFinite) return;
      if (!mounted) return;
      setState(() => _frac = Offset(dx.clamp(0.0, 1.0), dy.clamp(0.0, 1.0)));
    } catch (_) {
      // Storage unavailable (private mode, blocked): keep the default.
    }
  }

  Future<void> _savePosition() async {
    final f = _frac;
    if (f == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          chatbotPositionPrefsKey, [f.dx.toString(), f.dy.toString()]);
    } catch (_) {}
  }

  /// The rectangle the bubble's top-left may occupy.
  Rect _range(Size size, EdgeInsets pad) {
    final minX = pad.left;
    final maxX = math.max(minX, size.width - pad.right - _bubbleSize);
    final minY = pad.top;
    final maxY = math.max(minY, size.height - pad.bottom - _bubbleSize);
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Offset _bubbleTopLeft(Size size, EdgeInsets pad) {
    final r = _range(size, pad);
    final f = _frac;
    if (f == null) {
      return Offset(
        (r.right - _defaultRightGap).clamp(r.left, r.right),
        (r.bottom - _defaultBottomGap).clamp(r.top, r.bottom),
      );
    }
    return Offset(r.left + f.dx * r.width, r.top + f.dy * r.height);
  }

  void _moveBy(Offset delta, Size size, EdgeInsets pad) {
    final r = _range(size, pad);
    final cur = _bubbleTopLeft(size, pad) + delta;
    final x = cur.dx.clamp(r.left, r.right);
    final y = cur.dy.clamp(r.top, r.bottom);
    setState(() => _frac = Offset(
          r.width == 0 ? 0 : (x - r.left) / r.width,
          r.height == 0 ? 0 : (y - r.top) / r.height,
        ));
  }

  // ── open / close ───────────────────────────────────────────────────────

  void _openPanel() {
    setState(() => _open = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocus.requestFocus();
    });
    _scrollToEnd();
  }

  void _closePanel() {
    if (!_open) return;
    setState(() => _open = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bubbleFocus.requestFocus();
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    });
  }

  // ── messaging ──────────────────────────────────────────────────────────

  List<ChatTurn> _history() {
    final turns = [
      for (final m in _messages)
        ChatTurn(fromUser: m.fromUser, text: m.text),
    ];
    return turns.length > ChatbotService.maxHistoryTurns
        ? turns.sublist(turns.length - ChatbotService.maxHistoryTurns)
        : turns;
  }

  Future<void> _submit() => _send(_input.text);

  Future<void> _send(String raw, {bool isRetry = false}) async {
    final text = raw.trim();
    if (_sending || text.isEmpty) return; // one request at a time
    if (text.length > ChatbotService.maxMessageChars) {
      setState(() => _error = const ChatbotException(
          'That message is too long. Please keep it under 1000 characters.',
          code: 'too_long',
          retryable: false));
      return;
    }
    final history = _history();
    setState(() {
      _sending = true;
      _error = null;
      _failedMessage = null;
      if (!isRetry) _messages.add(_Msg(text, fromUser: true));
      _input.clear();
    });
    _scrollToEnd();
    try {
      final reply = await ChatbotService.instance.send(text, history);
      if (!mounted) return;
      setState(() {
        _messages.add(
            _Msg(reply.text, fromUser: false, refusal: !reply.inScope));
        _sending = false;
      });
    } on ChatbotException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _failedMessage = text;
        _sending = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = const ChatbotException(
            'Something went wrong. Please try again.');
        _failedMessage = text;
        _sending = false;
      });
    }
    _scrollToEnd();
  }

  void _retry() {
    final msg = _failedMessage;
    if (msg != null) _send(msg, isRetry: true);
  }

  // ── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final pad = media.padding + const EdgeInsets.all(_edge);
    final bubble = _bubbleTopLeft(size, pad);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        textDirection: TextDirection.ltr,
        children: [
          if (_open)
            Positioned.fill(
              child: GestureDetector(
                key: const Key('chatbot-barrier'),
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: _closePanel,
              ),
            ),
          if (_open) _buildPanel(context, size, media, bubble),
          Positioned(
            left: bubble.dx,
            top: bubble.dy,
            child: _buildBubble(size, pad),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(Size size, EdgeInsets pad) {
    return FocusableActionDetector(
      focusNode: _bubbleFocus,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft):
            _NudgeIntent(Offset(-24, 0)),
        SingleActivator(LogicalKeyboardKey.arrowRight):
            _NudgeIntent(Offset(24, 0)),
        SingleActivator(LogicalKeyboardKey.arrowUp):
            _NudgeIntent(Offset(0, -24)),
        SingleActivator(LogicalKeyboardKey.arrowDown):
            _NudgeIntent(Offset(0, 24)),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          _open ? _closePanel() : _openPanel();
          return null;
        }),
        _NudgeIntent: CallbackAction<_NudgeIntent>(onInvoke: (i) {
          _moveBy(i.delta, size, pad);
          _savePosition();
          return null;
        }),
      },
      child: Semantics(
        button: true,
        expanded: _open,
        label: _open
            ? 'Close Poultry and Featherflow assistant'
            : 'Open Poultry and Featherflow assistant. Drag or use arrow keys to move.',
        child: GestureDetector(
          key: const Key('chatbot-bubble'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _open ? _closePanel() : _openPanel(),
          onPanStart: (_) => setState(() => _dragging = true),
          onPanUpdate: (d) => _moveBy(d.delta, size, pad),
          onPanEnd: (_) {
            setState(() => _dragging = false);
            _savePosition();
          },
          onPanCancel: () => setState(() => _dragging = false),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 120),
            scale: _dragging ? 1.08 : 1,
            child: Container(
              width: _bubbleSize,
              height: _bubbleSize,
              decoration: BoxDecoration(
                color: AppColors.navigationSurface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.secondary, width: 2),
                boxShadow: const [
                  BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 12,
                      offset: Offset(0, 4)),
                ],
              ),
              child: Icon(
                _open ? Icons.close_rounded : Icons.chat_bubble_rounded,
                color: AppColors.navigationIconColor,
                size: 26,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(
      BuildContext context, Size size, MediaQueryData media, Offset bubble) {
    final keyboard = media.viewInsets.bottom;
    final compact = size.width < 600;
    final availableH =
        size.height - media.padding.top - keyboard - _edge * 2;
    final width = math.min(380.0, size.width - _edge * 2);
    final height = math.max(
        240.0,
        math.min(compact ? availableH * 0.6 : 540.0, availableH)
            .clamp(0.0, availableH));
    double left;
    double top;
    if (compact) {
      // Phones: dock at the bottom (above the keyboard), top 40% of the
      // screen stays visible and tappable (tap there closes the panel).
      left = (size.width - width) / 2;
      top = size.height - keyboard - height - _edge - media.padding.bottom;
    } else {
      final bubbleOnRight = bubble.dx + _bubbleSize / 2 > size.width / 2;
      left = bubbleOnRight
          ? bubble.dx + _bubbleSize - width
          : bubble.dx;
      final above = bubble.dy - height - _edge;
      top = above >= media.padding.top + _edge
          ? above
          : bubble.dy + _bubbleSize + _edge;
      top = top.clamp(media.padding.top + _edge,
          math.max(media.padding.top + _edge, size.height - keyboard - height - _edge));
    }
    left = left.clamp(_edge, math.max(_edge, size.width - width - _edge));

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Semantics(
        container: true,
        label: 'Poultry and Featherflow assistant chat',
        child: FocusScope(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): _closePanel,
            },
            child: _ChatPanel(
              messages: _messages,
              sending: _sending,
              error: _error,
              input: _input,
              inputFocus: _inputFocus,
              scroll: _scroll,
              onSend: _submit,
              onRetry: _retry,
              onClose: _closePanel,
              onSuggestion: (s) => _send(s),
              onChanged: () => setState(() {}),
            ),
          ),
        ),
      ),
    );
  }
}

class _NudgeIntent extends Intent {
  const _NudgeIntent(this.delta);
  final Offset delta;
}

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({
    required this.messages,
    required this.sending,
    required this.error,
    required this.input,
    required this.inputFocus,
    required this.scroll,
    required this.onSend,
    required this.onRetry,
    required this.onClose,
    required this.onSuggestion,
    required this.onChanged,
  });

  final List<_Msg> messages;
  final bool sending;
  final ChatbotException? error;
  final TextEditingController input;
  final FocusNode inputFocus;
  final ScrollController scroll;
  final VoidCallback onSend;
  final VoidCallback onRetry;
  final VoidCallback onClose;
  final ValueChanged<String> onSuggestion;
  final VoidCallback onChanged;

  static const _suggestions = [
    'How do I keep broiler chicks warm?',
    'My hens stopped laying eggs',
    'How do I order feed in Featherflow?',
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('chatbot-panel'),
      color: AppColors.surface,
      elevation: 12,
      shadowColor: AppColors.shadow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _header(),
          Expanded(child: _body(context)),
          if (error != null) _errorBar(),
          _composer(),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      color: AppColors.navigationSurface,
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          const Icon(Icons.egg_alt_rounded,
              color: AppColors.navigationIconColor, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Poultry & Featherflow assistant',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: AppColors.navigationForegroundColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 14),
            ),
          ),
          IconButton(
            key: const Key('chatbot-close'),
            tooltip: 'Close assistant',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded,
                color: AppColors.navigationIconColor),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (messages.isEmpty && !sending) {
      return ListView(
        key: const Key('chatbot-empty'),
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Ask me about poultry farming — feed, housing, biosecurity, '
            'vaccination, flock health — or how to do something in Featherflow.',
            style: TextStyle(color: AppColors.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 12),
          for (final s in _suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ActionChip(
                label: Text(s),
                onPressed: () => onSuggestion(s),
                backgroundColor: AppColors.surfaceContainerHighest,
                side: const BorderSide(color: AppColors.outline),
              ),
            ),
          const SizedBox(height: 4),
          const Text(
            'General guidance only — not a veterinary diagnosis.',
            style: TextStyle(color: AppColors.hint, fontSize: 12),
          ),
        ],
      );
    }
    return Semantics(
      liveRegion: true,
      child: ListView.builder(
        key: const Key('chatbot-messages'),
        controller: scroll,
        padding: const EdgeInsets.all(12),
        itemCount: messages.length + (sending ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= messages.length) return _typing();
          return _bubble(messages[i]);
        },
      ),
    );
  }

  Widget _bubble(_Msg m) {
    final user = m.fromUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: user
              ? AppColors.primaryContainer
              : (m.refusal
                  ? AppColors.errorContainer
                  : AppColors.surfaceContainerHighest),
          borderRadius: BorderRadius.circular(14),
        ),
        child: SelectableText(
          m.text,
          style: TextStyle(
            color: user
                ? AppColors.onPrimary
                : (m.refusal
                    ? AppColors.onErrorContainer
                    : AppColors.onSurface),
            height: 1.35,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _typing() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const Key('chatbot-loading'),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.secondaryContainer),
            ),
            SizedBox(width: 10),
            Text('Thinking…',
                style: TextStyle(color: AppColors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _errorBar() {
    final e = error!;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('chatbot-error'),
        width: double.infinity,
        color: AppColors.errorContainer,
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Icon(e.offline ? Icons.wifi_off_rounded : Icons.error_outline,
                size: 18, color: AppColors.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(e.message,
                  style: const TextStyle(
                      color: AppColors.onErrorContainer, fontSize: 13)),
            ),
            if (e.retryable)
              TextButton(
                key: const Key('chatbot-retry'),
                onPressed: sending ? null : onRetry,
                child: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    final canSend = !sending && input.text.trim().isNotEmpty;
    return Container(
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider))),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('chatbot-input'),
              controller: input,
              focusNode: inputFocus,
              enabled: true,
              minLines: 1,
              maxLines: 4,
              maxLength: ChatbotService.maxMessageChars,
              textInputAction: TextInputAction.send,
              onChanged: (_) => onChanged(),
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Ask about poultry or Featherflow…',
                counterText: '',
                isDense: true,
                border: InputBorder.none,
              ),
            ),
          ),
          IconButton(
            key: const Key('chatbot-send'),
            tooltip: 'Send message',
            onPressed: canSend ? onSend : null,
            icon: Icon(Icons.send_rounded,
                color: canSend ? AppColors.secondaryContainer : AppColors.disabled),
          ),
        ],
      ),
    );
  }
}
