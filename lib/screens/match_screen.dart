import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/ws/v2_types.dart';
import '../services/ws/ws_service.dart';

class MatchScreen extends StatefulWidget {
  const MatchScreen({
    super.key,
    required this.ws,
    required this.matchId,
  });

  final WsService ws;
  final String matchId;

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  StreamSubscription? _sub;

  Map<String, Object?>? _match;
  Map<String, Object?>? _game;

  @override
  void initState() {
    super.initState();

    // Always refresh snapshot on entry.
    if (widget.ws.state == WsConnectionState.connected) {
      widget.ws.send(WsInFrame(msg: WsMsg.matchSnapshotGet(matchId: widget.matchId)));
    }

    _sub = widget.ws.incoming.listen(_handleFrame);
  }

  void _handleFrame(WsOutFrame frame) {
    final type = frame.msg.type;
    final data = frame.msg.data;
    if (data == null) return;

    if (type == 'match.snapshot' || type == 'match.update') {
      final m = (data['match'] as Map?)?.cast<String, Object?>();
      if (m == null) return;
      setState(() {
        _match = m;
      });
      return;
    }

    if (type == 'game.snapshot' || type == 'game.update') {
      final g = (data['game'] as Map?)?.cast<String, Object?>();
      if (g == null) return;
      setState(() {
        _game = g;
      });
      return;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matchPretty = _match == null ? '(none yet)' : const JsonEncoder.withIndent('  ').convert(_match);
    final gamePretty = _game == null ? '(none yet)' : const JsonEncoder.withIndent('  ').convert(_game);

    return Scaffold(
      appBar: AppBar(
        title: Text('Match ${widget.matchId}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListenableBuilder(
              listenable: widget.ws,
              builder: (context, _) => Text('WS: ${widget.ws.state}'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: widget.ws.state == WsConnectionState.connected
                  ? () {
                      widget.ws.send(
                        WsInFrame(msg: WsMsg.matchSnapshotGet(matchId: widget.matchId)),
                      );
                    }
                  : null,
              child: const Text('Refresh match.snapshot'),
            ),
            const SizedBox(height: 12),
            const Text('Match:'),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Text(matchPretty, style: const TextStyle(fontFamily: 'monospace')),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Game:'),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Text(gamePretty, style: const TextStyle(fontFamily: 'monospace')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
