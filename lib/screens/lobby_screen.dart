import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';
import '../services/ws/v2_types.dart';
import '../services/ws/ws_service.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key, required this.auth, required this.ws});

  final AuthService auth;
  final WsService ws;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  StreamSubscription? _sub;
  String _log = '';

  List<Map<String, Object?>> _matches = const [];

  @override
  void initState() {
    super.initState();

    widget.ws.addListener(_onWsChanged);

    _sub = widget.ws.incoming.listen((frame) {
      setState(() {
        _log = '${frame.msg.type}\n$_log';
      });

      _handleFrame(frame);
    });
  }

  void _onWsChanged() {
    if (!mounted) return;
    if (widget.ws.state == WsConnectionState.connected) {
      // Always refresh lobby list when we connect/reconnect.
      widget.ws.send(WsInFrame(msg: WsMsg.lobbySnapshotGet()));
    }
  }

  void _handleFrame(WsOutFrame frame) {
    final type = frame.msg.type;
    final data = frame.msg.data;

    switch (type) {
      case 'lobby.snapshot':
        final matches = (data['matches'] as List?)
                ?.whereType<Map>()
                .map((m) => m.cast<String, Object?>())
                .toList() ??
            const <Map<String, Object?>>[];
        setState(() {
          _matches = matches;
        });
        return;

      case 'lobby.match.upsert':
        final match = (data['match'] as Map?)?.cast<String, Object?>();
        if (match == null) return;
        setState(() {
          final id = match['id'];
          _matches = [
            for (final m in _matches)
              if (m['id'] != id) m,
            match,
          ];
        });
        return;

      case 'lobby.match.remove':
        final matchId = data['match_id'];
        if (matchId == null) return;
        setState(() {
          _matches = [
            for (final m in _matches)
              if (m['id'] != matchId) m,
          ];
        });
        return;

      default:
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lobby'),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: () => widget.auth.logout(),
            icon: const Icon(Icons.logout),
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
              builder: (context, _) {
                return Text('WS: ${widget.ws.state}');
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () => unawaited(widget.ws.connect()),
                  child: const Text('Connect /v2/ws'),
                ),
                OutlinedButton(
                  onPressed: () => unawaited(widget.ws.disconnect()),
                  child: const Text('Disconnect'),
                ),
                OutlinedButton(
                  onPressed: widget.ws.state == WsConnectionState.connected
                      ? () {
                          widget.ws.send(
                            WsInFrame(msg: WsMsg.ping(clientTimeMs: 0)),
                          );
                        }
                      : null,
                  child: const Text('ping'),
                ),
                OutlinedButton(
                  onPressed: widget.ws.state == WsConnectionState.connected
                      ? () {
                          widget.ws.send(
                            WsInFrame(msg: WsMsg.lobbySnapshotGet()),
                          );
                        }
                      : null,
                  child: const Text('lobby.snapshot.get'),
                ),
                OutlinedButton(
                  onPressed: () {
                    context.go('/table?me=me&players=me,p2');
                  },
                  child: const Text('Table (2p mock)'),
                ),
                OutlinedButton(
                  onPressed: () {
                    context.go('/table?me=me&players=me,p2,p3,p4');
                  },
                  child: const Text('Table (4p mock)'),
                ),
                OutlinedButton(
                  onPressed: () {
                    context.go('/table?me=me&players=me,p2,p3,p4,p5,p6');
                  },
                  child: const Text('Table (6p mock)'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.ws.lastError != null)
              Text(
                widget.ws.lastError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            const Text('Lobby matches:'),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _matches.length,
                itemBuilder: (context, idx) {
                  final m = _matches[idx];
                  final id = (m['id'] as String?) ?? '<unknown>';
                  final phase = (m['phase'] as String?) ?? '?';

                  final players = (m['players'] as List?)
                          ?.whereType<Map>()
                          .map((p) => p['name'])
                          .whereType<String>()
                          .toList() ??
                      const <String>[];

                  return Card(
                    child: ListTile(
                      title: Text('Match $id'),
                      subtitle: Text('$phase • ${players.join(', ')}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        // TODO: join match + navigate to match/table.
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            const Text('Incoming (latest first):'),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: SingleChildScrollView(
                child: Text(
                  _log,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
