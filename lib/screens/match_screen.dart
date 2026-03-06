import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
  Map<String, Object?>? _me;
  Map<String, Object?>? _game;

  String? _lastPhase;
  bool _navigatedToTable = false;

  @override
  void initState() {
    super.initState();

    widget.ws.addListener(_onWsChanged);

    // Ensure we're connected (no-op if already connected).
    unawaited(widget.ws.connect());

    // Always refresh snapshot on entry.
    if (widget.ws.state == WsConnectionState.connected) {
      widget.ws.send(WsInFrame(msg: WsMsg.matchSnapshotGet(matchId: widget.matchId)));
    }

    _sub = widget.ws.incoming.listen(_handleFrame);
  }

  void _onWsChanged() {
    if (!mounted) return;
    if (widget.ws.state == WsConnectionState.connected) {
      widget.ws.send(WsInFrame(msg: WsMsg.matchSnapshotGet(matchId: widget.matchId)));
    }
  }

  void _handleFrame(WsOutFrame frame) {
    final type = frame.msg.type;
    final data = frame.msg.data;
    if (data == null) return;

    if (type == 'match.snapshot' || type == 'match.update') {
      final m = (data['match'] as Map?)?.cast<String, Object?>();
      if (m == null) return;

      final matchId = m['id'] as String?;
      if (matchId != null && matchId != widget.matchId) return;

      final me = (data['me'] as Map?)?.cast<String, Object?>();
      final phase = m['phase'] as String?;
      final prevPhase = _lastPhase;

      setState(() {
        _match = m;
        if (me != null) _me = me;
        _lastPhase = phase ?? _lastPhase;
      });

      // When match starts, proactively fetch gameplay snapshot and move to table.
      if (phase == 'started' && _game == null) {
        if (widget.ws.state == WsConnectionState.connected) {
          widget.ws.send(WsInFrame(msg: WsMsg.gameSnapshotGet(matchId: widget.matchId)));
        }
      }

      if (phase == 'started' && prevPhase != 'started' && !_navigatedToTable) {
        _navigatedToTable = true;
        if (!mounted) return;
        context.go('/table/${widget.matchId}');
      }

      return;
    }

    if (type == 'game.snapshot' || type == 'game.update') {
      final matchId = data['match_id'] as String?;
      if (matchId != null && matchId != widget.matchId) return;

      final g = (data['game'] as Map?)?.cast<String, Object?>();
      if (g == null) return;

      final me = (data['me'] as Map?)?.cast<String, Object?>();

      setState(() {
        _game = g;
        if (me != null) _me = me;
      });
      return;
    }

    if (type == 'match.left') {
      final matchId = data['match_id'] as String?;
      if (matchId != widget.matchId) return;
      if (!mounted) return;
      context.go('/lobby');
      return;
    }

    if (type == 'error') {
      final code = data['code'] as String?;
      final msg = data['message'] as String?;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${code ?? 'ERROR'}: ${msg ?? 'request failed'}')),
      );
      return;
    }
  }

  @override
  void dispose() {
    widget.ws.removeListener(_onWsChanged);
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matchPretty =
        _match == null ? '(none yet)' : const JsonEncoder.withIndent('  ').convert(_match);
    final gamePretty =
        _game == null ? '(none yet)' : const JsonEncoder.withIndent('  ').convert(_game);

    final players = (_match?['players'] as List?)
            ?.whereType<Map>()
            .map((p) => p.cast<String, Object?>())
            .toList() ??
        const <Map<String, Object?>>[];

    final meSeatIdx = _me?['seat_idx'] as int?;
    final ownerSeatIdx = _match?['owner_seat_idx'] as int?;
    final phase = _match?['phase'] as String?;

    final iAmOwner = meSeatIdx != null && ownerSeatIdx != null && meSeatIdx == ownerSeatIdx;
    final myReady = (meSeatIdx != null && meSeatIdx < players.length)
        ? (players[meSeatIdx]['ready'] as bool?)
        : null;

    final allReady = players.isNotEmpty && players.every((p) => (p['ready'] as bool?) == true);

    return Scaffold(
      appBar: AppBar(
        title: Text('Match ${widget.matchId}'),
        actions: [
          IconButton(
            tooltip: 'Open table',
            onPressed: () => context.go('/table/${widget.matchId}'),
            icon: const Icon(Icons.table_restaurant),
          ),
          IconButton(
            tooltip: 'Leave match',
            onPressed: widget.ws.state == WsConnectionState.connected
                ? () {
                    widget.ws.send(
                      WsInFrame(msg: WsMsg.matchLeave(matchId: widget.matchId)),
                    );
                  }
                : null,
            icon: const Icon(Icons.exit_to_app),
          ),
        ],
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: widget.ws.state == WsConnectionState.connected
                      ? () {
                          widget.ws.send(
                            WsInFrame(msg: WsMsg.matchSnapshotGet(matchId: widget.matchId)),
                          );
                        }
                      : null,
                  child: const Text('match.snapshot.get'),
                ),
                OutlinedButton(
                  onPressed: widget.ws.state == WsConnectionState.connected
                      ? () {
                          widget.ws.send(
                            WsInFrame(msg: WsMsg.gameSnapshotGet(matchId: widget.matchId)),
                          );
                        }
                      : null,
                  child: const Text('game.snapshot.get'),
                ),
                FilledButton(
                  onPressed: widget.ws.state == WsConnectionState.connected && myReady != null
                      ? () {
                          widget.ws.send(
                            WsInFrame(
                              msg: WsMsg.matchReady(
                                matchId: widget.matchId,
                                ready: !myReady,
                              ),
                            ),
                          );
                        }
                      : null,
                  child: Text(myReady == true ? 'Set not ready' : 'Ready up'),
                ),
                FilledButton.tonal(
                  onPressed: widget.ws.state == WsConnectionState.connected &&
                          phase == 'lobby' &&
                          iAmOwner &&
                          allReady
                      ? () {
                          widget.ws.send(
                            WsInFrame(msg: WsMsg.matchStart(matchId: widget.matchId)),
                          );
                        }
                      : null,
                  child: const Text('Start match'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (phase != null)
              Text(
                'phase=$phase  me_seat_idx=${meSeatIdx ?? '?'}  owner_seat_idx=${ownerSeatIdx ?? '?'}  all_ready=$allReady',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            const SizedBox(height: 12),
            if (players.isNotEmpty) ...[
              const Text('Players:'),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: ListView.builder(
                  itemCount: players.length,
                  itemBuilder: (context, idx) {
                    final p = players[idx];
                    final name = p['name'] as String? ?? 'player';
                    final team = p['team']?.toString() ?? '?';
                    final ready = p['ready'] == true;

                    final tags = [
                      if (idx == meSeatIdx) 'me',
                      if (idx == ownerSeatIdx) 'owner',
                      if (ready) 'ready',
                    ];

                    return ListTile(
                      dense: true,
                      title: Text('$idx: $name'),
                      subtitle: Text('team=$team${tags.isEmpty ? '' : ' • ${tags.join(' • ')}'}'),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
            const Text('Match JSON:'),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Text(matchPretty, style: const TextStyle(fontFamily: 'monospace')),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Game JSON:'),
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
