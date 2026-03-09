import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/match_chat_controller.dart';
import '../chat/match_chat_message.dart';
import '../services/ws/v2_types.dart';
import '../services/ws/ws_service.dart';
import 'status_chip.dart';

class MatchChatPanel extends StatefulWidget {
  const MatchChatPanel({
    super.key,
    required this.ws,
    required this.roomId,
    this.maxHeight = 240,
    this.showEmojiRow = true,
    this.title = 'Match chat',
  });

  final WsService ws;
  final String roomId;
  final double maxHeight;
  final bool showEmojiRow;
  final String title;

  @override
  State<MatchChatPanel> createState() => _MatchChatPanelState();
}

class _MatchChatPanelState extends State<MatchChatPanel> {
  static const _emojiChoices = [
    '😀',
    '😂',
    '❤️',
    '🔥',
    '👍',
    '😢',
    '👏',
    '💯',
    '🤯',
    '🙌',
    '😮',
    '🥳',
  ];

  late final MatchChatController _controller;
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  StreamSubscription? _sub;
  String? _pendingJoinRequestId;
  String? _lastError;
  bool _shouldStickToBottom = true;
  DateTime? _lastJoinRequestedAt;

  @override
  void initState() {
    super.initState();
    _controller = MatchChatController();
    _inputController.addListener(_onComposerChanged);
    widget.ws.addListener(_handleWsChanged);
    _sub = widget.ws.incoming.listen(_handleFrame);
    _requestJoin(force: true);
  }

  @override
  void didUpdateWidget(MatchChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.roomId != oldWidget.roomId) {
      _controller.clear();
      _pendingJoinRequestId = null;
      _lastError = null;
      _requestJoin(force: true);
    }
  }

  void _handleWsChanged() {
    if (!mounted) return;
    if (widget.ws.state == WsConnectionState.connected) {
      _requestJoin();
    }
    setState(() {});
  }

  void _requestJoin({bool force = false}) {
    if (widget.ws.state != WsConnectionState.connected) return;
    final now = DateTime.now();
    if (!force) {
      final last = _lastJoinRequestedAt;
      if (last != null && now.difference(last) < const Duration(seconds: 2)) {
        return;
      }
    }

    final reqId = 'chat-join-${widget.roomId}-${now.microsecondsSinceEpoch}';
    _pendingJoinRequestId = reqId;
    _lastJoinRequestedAt = now;

    widget.ws.send(
      WsInFrame(
        id: reqId,
        msg: WsMsg.chatJoin(roomId: widget.roomId),
      ),
    );

    setState(() {
      _lastError = null;
    });
  }

  void _handleFrame(WsOutFrame frame) {
    final type = frame.msg.type;
    final data = frame.msg.data;
    if (data == null) return;

    if (type == 'chat.snapshot') {
      final room = (data['room'] as Map?)?.cast<String, Object?>();
      final roomId = room?['id'] as String?;
      if (roomId != widget.roomId) return;

      final messages = ((room?['messages'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => MatchChatMessage.fromJson(m.cast<String, Object?>()))
          .whereType<MatchChatMessage>()
          .toList();

      _controller.replaceAll(messages);

      if (_pendingJoinRequestId != null && frame.id == _pendingJoinRequestId) {
        _pendingJoinRequestId = null;
      }

      _lastError = null;

      if (mounted) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToBottom(force: true),
        );
      }
      return;
    }

    if (type == 'chat.message') {
      final roomId = data['room_id'] as String?;
      if (roomId != widget.roomId) return;

      final msgJson = (data['message'] as Map?)?.cast<String, Object?>();
      if (msgJson == null) return;

      final message = MatchChatMessage.fromJson(msgJson);
      if (message == null) return;

      final isNew = _controller.append(message);
      if (isNew) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
      return;
    }

    if (type == 'error' && _pendingJoinRequestId != null) {
      if (frame.id == _pendingJoinRequestId) {
        final code = data['code'] as String? ?? 'CHAT_ERROR';
        final msg = data['message'] as String? ?? 'chat join failed';
        _lastError = '$code: $msg';
        _pendingJoinRequestId = null;
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  void _scrollToBottom({bool force = false}) {
    if (!_scrollController.hasClients) return;
    if (!force && !_shouldStickToBottom) return;
    final position = _scrollController.position.maxScrollExtent;
    _scrollController.animateTo(
      position,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!_scrollController.hasClients) return false;
    final metrics = notification.metrics;
    final max = metrics.maxScrollExtent;
    final pixels = metrics.pixels;
    final atBottom = max <= 0 || pixels >= max - 24;
    if (atBottom != _shouldStickToBottom) {
      setState(() {
        _shouldStickToBottom = atBottom;
      });
    }
    return false;
  }

  void _sendMessage() {
    if (widget.ws.state != WsConnectionState.connected) return;
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    widget.ws.send(
      WsInFrame(
        msg: WsMsg.chatSay(roomId: widget.roomId, content: text),
      ),
    );
    _inputController.clear();
  }

  void _insertEmoji(String emoji) {
    final value = _inputController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final nextText = value.text.replaceRange(start, end, emoji);
    _inputController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  Future<void> _copyMessage(MatchChatMessage message) async {
    final text = '${message.userName}: ${message.content}'.trim();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied chat message')));
  }

  void _onComposerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    widget.ws.removeListener(_handleWsChanged);
    _sub?.cancel();
    _controller.dispose();
    _inputController.removeListener(_onComposerChanged);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final connected = widget.ws.state == WsConnectionState.connected;
    final canSend = connected && _inputController.text.trim().isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(widget.title, style: theme.textTheme.titleMedium),
                const Spacer(),
                StatusChip(
                  icon: connected ? Icons.wifi : Icons.wifi_off,
                  label: connected ? 'Connected' : 'Offline',
                  tone: connected ? scheme.primary : scheme.error,
                ),
                IconButton(
                  tooltip: 'Refresh chat',
                  onPressed: connected ? () => _requestJoin(force: true) : null,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_lastError != null) ...[
              const SizedBox(height: 8),
              Text(_lastError!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: widget.maxHeight,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  if (!_controller.isReady) {
                    return _ChatPlaceholder(
                      text: connected
                          ? 'Loading chat…'
                          : 'Connect to load chat history.',
                    );
                  }
                  if (_controller.isEmpty) {
                    return const _ChatPlaceholder(
                      text: 'No messages yet. Say hi! 👋',
                    );
                  }
                  final messages = _controller.messages;
                  return Stack(
                    children: [
                      NotificationListener<ScrollNotification>(
                        onNotification: _handleScrollNotification,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(
                            left: 4,
                            right: 4,
                            bottom: 12,
                          ),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[index];
                            return _ChatBubble(
                              message: msg,
                              onCopy: () => _copyMessage(msg),
                            );
                          },
                        ),
                      ),
                      if (!_shouldStickToBottom)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: IconButton.filledTonal(
                            tooltip: 'Jump to latest',
                            icon: const Icon(Icons.arrow_downward),
                            onPressed: () => _scrollToBottom(force: true),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            if (widget.showEmojiRow) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final emoji in _emojiChoices)
                    OutlinedButton(
                      onPressed: connected ? () => _insertEmoji(emoji) : null,
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 18)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    enabled: connected,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Message',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: canSend ? _sendMessage : null,
                  icon: const Icon(Icons.send),
                  tooltip: 'Send',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatPlaceholder extends StatelessWidget {
  const _ChatPlaceholder({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: scheme.surfaceContainerHighest,
      ),
      padding: const EdgeInsets.all(16),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, required this.onCopy});

  final MatchChatMessage message;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final teamColor = _teamColor(scheme, message.teamIdx);
    final bg = message.system
        ? scheme.surfaceVariant
        : scheme.surfaceContainerHigh;
    final borderColor = message.system
        ? scheme.outlineVariant
        : teamColor.withOpacity(0.5);

    return InkWell(
      onTap: onCopy,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: teamColor,
                  foregroundColor: scheme.onPrimary,
                  child: Text(
                    message.initials,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message.system ? 'System' : message.userName,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: message.system ? scheme.onSurface : teamColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatTime(message.timestamp),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _MiniChip(
                  icon: message.isSpectator
                      ? Icons.visibility_outlined
                      : Icons.event_seat,
                  label: message.isSpectator
                      ? 'Spectator'
                      : 'Seat ${message.seatIdx}',
                ),
                if (message.teamIdx != null)
                  _MiniChip(
                    icon: Icons.groups_2,
                    label: 'Team ${message.teamIdx}',
                  ),
                if (message.system)
                  const _MiniChip(icon: Icons.info, label: 'System'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              message.content.isEmpty
                  ? (message.system ? '(system message)' : '(empty)')
                  : message.content,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

Color _teamColor(ColorScheme scheme, int? team) {
  switch (team) {
    case 0:
      return scheme.primary;
    case 1:
      return scheme.tertiary;
    default:
      return scheme.outline;
  }
}

String _formatTime(DateTime dt) {
  final hours = dt.hour.toString().padLeft(2, '0');
  final minutes = dt.minute.toString().padLeft(2, '0');
  return '$hours:$minutes';
}
