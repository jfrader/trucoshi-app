import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../platform/platform_caps.dart';
import '../services/auth_service.dart';
import '../services/ws/v2_types.dart';
import '../services/ws/ws_service.dart';

enum _TeamChoice {
  auto,
  team0,
  team1,
}

int? _teamFromChoice(_TeamChoice c) {
  return switch (c) {
    _TeamChoice.auto => null,
    _TeamChoice.team0 => 0,
    _TeamChoice.team1 => 1,
  };
}

int? _readMaxPlayers(Map<String, Object?> match) {
  final direct = match['max_players'];
  if (direct is int) return direct;
  if (direct is num) return direct.toInt();

  final opts = match['options'];
  if (opts is Map) {
    final v = opts['max_players'];
    if (v is int) return v;
    if (v is num) return v.toInt();
  }

  return null;
}

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key, required this.auth, required this.ws, required this.caps});

  final AuthService auth;
  final WsService ws;
  final PlatformCaps caps;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  StreamSubscription? _sub;
  String _log = '';

  final _guestNameCtrl = TextEditingController();

  List<Map<String, Object?>> _matches = const [];

  String? _pendingActionId;
  String? _pendingMatchId;

  @override
  void initState() {
    super.initState();

    _guestNameCtrl.text = widget.auth.displayName;

    widget.auth.addListener(_onAuthChanged);
    widget.ws.addListener(_onWsChanged);

    // Lobby UX: connect automatically once we have either guest mode or an
    // access token.
    if (widget.auth.isLoggedIn) {
      unawaited(widget.ws.connect());
    }

    _sub = widget.ws.incoming.listen((frame) {
      if (!mounted) return;
      setState(() {
        _log = '${frame.msg.type}\n$_log';
      });

      _handleFrame(frame);
    });
  }

  void _onAuthChanged() {
    if (!mounted) return;

    if (!widget.auth.isLoggedIn) {
      setState(() {
        _matches = const [];
        _pendingActionId = null;
        _pendingMatchId = null;
      });
      return;
    }

    if (widget.ws.state == WsConnectionState.disconnected) {
      unawaited(widget.ws.connect());
    }
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
    _guestNameCtrl.text = widget.auth.displayName;
  }

  Future<void> _showJoinMatchDialog(
    BuildContext context, {
    required String matchId,
  }) async {
    var teamChoice = _TeamChoice.auto;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Join match'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Joining as: ${widget.auth.displayName}'),
                  const SizedBox(height: 12),
                  const Text('Team (optional):'),
                  const SizedBox(height: 8),
                  SegmentedButton<_TeamChoice>(
                    segments: const [
                      ButtonSegment(value: _TeamChoice.auto, label: Text('Auto')),
                      ButtonSegment(value: _TeamChoice.team0, label: Text('Team 0')),
                      ButtonSegment(value: _TeamChoice.team1, label: Text('Team 1')),
                    ],
                    selected: {teamChoice},
                    onSelectionChanged: (set) {
                      setLocalState(() {
                        teamChoice = set.first;
                      });
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
                  child: const Text('Join'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;

    await _joinMatch(
      context,
      matchId: matchId,
      team: _teamFromChoice(teamChoice),
    );
  }

  Future<void> _joinMatch(
    BuildContext context, {
    required String matchId,
    int? team,
  }) async {
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
          team: team,
        ),
      ),
    );
  }

  Future<void> _watchMatch(
    BuildContext context, {
    required String matchId,
  }) async {
    final actionId = 'watch-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _pendingActionId = actionId;
      _pendingMatchId = matchId;
    });

    widget.ws.send(
      WsInFrame(
        id: actionId,
        msg: WsMsg.matchWatch(matchId: matchId),
      ),
    );
  }

  Future<void> _showCreateMatchDialog(BuildContext context) async {
    int maxPlayers = 2;
    var teamChoice = _TeamChoice.auto;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Create match'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('You will create as: ${widget.auth.displayName}'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: maxPlayers,
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
                      setLocalState(() {
                        maxPlayers = v;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('Team (optional):'),
                  const SizedBox(height: 8),
                  SegmentedButton<_TeamChoice>(
                    segments: const [
                      ButtonSegment(value: _TeamChoice.auto, label: Text('Auto')),
                      ButtonSegment(value: _TeamChoice.team0, label: Text('Team 0')),
                      ButtonSegment(value: _TeamChoice.team1, label: Text('Team 1')),
                    ],
                    selected: {teamChoice},
                    onSelectionChanged: (set) {
                      setLocalState(() {
                        teamChoice = set.first;
                      });
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
          team: _teamFromChoice(teamChoice),
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

          if (matchId != null && (_pendingMatchId == null || _pendingMatchId == matchId)) {
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
    widget.auth.removeListener(_onAuthChanged);
    widget.ws.removeListener(_onWsChanged);
    _sub?.cancel();
    _guestNameCtrl.dispose();
    super.dispose();
  }

  Widget _buildUnauthedBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Welcome',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            widget.caps.supportsWsAuthHeaders
                ? 'Pick a name and jump into the lobby as a guest, or sign in.'
                : 'Pick a name and jump into the lobby as a guest. (Web is guest-only for now.)',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _guestNameCtrl,
            decoration: const InputDecoration(
              labelText: 'Display name',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              widget.auth.continueAsGuest(displayName: _guestNameCtrl.text);
              unawaited(widget.ws.connect());
            },
            child: const Text('Continue as guest'),
          ),
          const SizedBox(height: 8),
          if (widget.caps.supportsWsAuthHeaders)
            OutlinedButton(
              onPressed: () => context.go('/login'),
              child: const Text('Login / Register'),
            ),
          const SizedBox(height: 12),
          Text(
            'Backend URL comes from --dart-define=TRUCOSHI_BACKEND_URL',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildLobbyBody(BuildContext context) {
    return Padding(
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
              final rtt = widget.ws.lastPongRttMs;
              final ver = widget.ws.serverVersion;
              final sid = widget.ws.sessionId;

              final extras = [
                if (ver != null) 'v=$ver',
                if (sid != null) 'sid=$sid',
                if (rtt != null) 'rtt=${rtt}ms',
              ];

              return Text(
                'WS: ${widget.ws.state}${extras.isEmpty ? '' : '  •  ${extras.join("  •  ")}'}',
              );
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

                final maxPlayers = _readMaxPlayers(m);
                final needsTeamChoice = (maxPlayers ?? 2) >= 4;

                final sizeLabel = maxPlayers == null
                    ? ''
                    : ' • ${players.length}/$maxPlayers';
                final namesLabel = players.isEmpty ? '' : ' • ${players.join(', ')}';

                return Card(
                  child: ListTile(
                    title: Text('Match $id'),
                    subtitle: Text('$phase$sizeLabel$namesLabel'),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: widget.ws.state == WsConnectionState.connected
                              ? () => unawaited(_watchMatch(context, matchId: id))
                              : null,
                          child: const Text('Spectate'),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () {
                      if (needsTeamChoice) {
                        unawaited(_showJoinMatchDialog(context, matchId: id));
                      } else {
                        unawaited(_joinMatch(context, matchId: id));
                      }
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = widget.auth.isLoggedIn;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lobby'),
        actions: [
          if (!isLoggedIn) ...[
            if (widget.caps.supportsWsAuthHeaders)
              IconButton(
                tooltip: 'Login',
                onPressed: () => context.go('/login'),
                icon: const Icon(Icons.login),
              ),
          ] else if (widget.auth.isGuest) ...[
            if (widget.caps.supportsWsAuthHeaders)
              IconButton(
                tooltip: 'Login (upgrade from guest)',
                onPressed: () => context.go('/login'),
                icon: const Icon(Icons.login),
              ),
            IconButton(
              tooltip: 'Logout',
              onPressed: () => widget.auth.logout(),
              icon: const Icon(Icons.logout),
            ),
          ] else ...[
            IconButton(
              tooltip: 'Logout',
              onPressed: () => widget.auth.logout(),
              icon: const Icon(Icons.logout),
            ),
          ],
        ],
      ),
      body: isLoggedIn ? _buildLobbyBody(context) : _buildUnauthedBody(context),
    );
  }
}
