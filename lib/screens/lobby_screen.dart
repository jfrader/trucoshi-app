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

  String? _pendingActionId;
  String? _pendingMatchId;

  @override
  void initState() {
    super.initState();

    widget.ws.addListener(_onWsChanged);

    // Lobby UX: attempt to connect automatically. Guest mode is supported.
    unawaited(widget.ws.connect());

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

  Future<void> _showDisplayNameDialog(BuildContext context) async {
    final ctrl = TextEditingController(text: widget.auth.displayName);

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Display name'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
            autocorrect: false,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    widget.auth.setDisplayName(ctrl.text);
  }

  Future<void> _joinMatch(BuildContext context, {required String matchId}) async {
    final actionId = 'join-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _pendingActionId = actionId;
      _pendingMatchId = matchId;
    });

    widget.ws.send(
      WsInFrame(
        id: actionId,
        msg: WsMsg.matchJoin(
          matchId: matchId,
          name: widget.auth.displayName,
        ),
      ),
    );
  }

  Future<void> _showCreateMatchDialog(BuildContext context) async {
    int maxPlayers = 2;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create match'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('You will create as: ${widget.auth.displayName}'),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: maxPlayers,
                decoration: const InputDecoration(
                  labelText: 'Max players',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 2, child: Text('2 (1v1)')),
                  DropdownMenuItem(value: 4, child: Text('4 (2v2)')),
                  DropdownMenuItem(value: 6, child: Text('6 (3v3)')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  maxPlayers = v;
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (created != true) return;

    final actionId = 'create-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _pendingActionId = actionId;
      _pendingMatchId = null;
    });

    widget.ws.send(
      WsInFrame(
        id: actionId,
        msg: WsMsg.matchCreate(
          name: widget.auth.displayName,
          maxPlayers: maxPlayers,
          // Let the server use defaults for the rest.
        ),
      ),
    );
  }

  void _handleFrame(WsOutFrame frame) {
    final type = frame.msg.type;
    final data = frame.msg.data;
    if (data == null) return;

    switch (type) {
      case 'match.snapshot':
        // If this is the result of a create/join action, navigate to the match.
        if (_pendingActionId != null && frame.id == _pendingActionId) {
          final match = (data['match'] as Map?)?.cast<String, Object?>();
          final matchId = match?['id'] as String?;

          if (matchId != null &&
              (_pendingMatchId == null || _pendingMatchId == matchId)) {
            setState(() {
              _pendingActionId = null;
              _pendingMatchId = null;
            });

            if (!mounted) return;
            context.go('/match/$matchId');
          }
        }
        return;

      case 'error':
        if (_pendingActionId != null && frame.id == _pendingActionId) {
          final code = data['code'] as String?;
          final msg = data['message'] as String?;
          setState(() {
            _pendingActionId = null;
            _pendingMatchId = null;
          });

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${code ?? 'ERROR'}: ${msg ?? 'request failed'}')),
          );
        }
        return;

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
              listenable: widget.auth,
              builder: (context, _) {
                final mode = widget.auth.isGuest ? 'guest' : 'auth';
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        'You: ${widget.auth.displayName} ($mode)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit display name',
                      onPressed: () => unawaited(_showDisplayNameDialog(context)),
                      icon: const Icon(Icons.edit),
                    ),
                  ],
                );
              },
            ),
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
                  onPressed: widget.ws.state == WsConnectionState.connected
                      ? null
                      : () => unawaited(widget.ws.connect()),
                  child: const Text('Connect'),
                ),
                OutlinedButton(
                  onPressed: widget.ws.state == WsConnectionState.connected
                      ? () => unawaited(widget.ws.disconnect())
                      : null,
                  child: const Text('Disconnect'),
                ),
                OutlinedButton(
                  onPressed: widget.ws.state == WsConnectionState.connected
                      ? () {
                          widget.ws.send(
                            WsInFrame(msg: WsMsg.lobbySnapshotGet()),
                          );
                        }
                      : null,
                  child: const Text('Refresh lobby'),
                ),
                FilledButton.tonal(
                  onPressed: widget.ws.state == WsConnectionState.connected
                      ? () => unawaited(_showCreateMatchDialog(context))
                      : null,
                  child: const Text('Create match'),
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
                      onTap: () => unawaited(_joinMatch(context, matchId: id)),
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
