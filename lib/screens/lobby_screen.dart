import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../platform/platform_caps.dart';
import '../services/auth_service.dart';
import '../services/ws/v2_types.dart';
import '../services/ws/ws_service.dart';

enum _TeamChoice { auto, team0, team1 }

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

int? _readSpectatorCount(Map<String, Object?> match) {
  final raw = match['spectator_count'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return null;
}

List<Map<String, Object?>> _extractActiveMatches(Object? raw) {
  if (raw is! List) return const [];

  final out = <Map<String, Object?>>[];
  for (final entry in raw) {
    final summary = _extractActiveMatch(entry);
    if (summary != null) out.add(summary);
  }
  return out;
}

Map<String, Object?>? _extractActiveMatch(Object? raw) {
  if (raw is! Map) return null;
  final map = raw.cast<String, Object?>();
  final match = map['match'];
  final me = map['me'];

  if (match is! Map || me is! Map) return null;

  return {
    'match': match.cast<String, Object?>(),
    'me': me.cast<String, Object?>(),
  };
}

int? _estimateOnlinePlayers(
  List<Map<String, Object?>> lobby,
  List<Map<String, Object?>> active,
) {
  final names = <String>{};

  void addPlayers(Object? rawPlayers) {
    if (rawPlayers is! List) return;
    for (final p in rawPlayers) {
      if (p is! Map) continue;
      final name = p['name'];
      if (name is String && name.trim().isNotEmpty) {
        names.add(name.trim());
      }
    }
  }

  for (final match in lobby) {
    addPlayers(match['players']);
  }

  for (final summary in active) {
    final match = summary['match'];
    if (match is Map) {
      addPlayers(match['players']);
    }
  }

  return names.isEmpty ? null : names.length;
}

const _defaultAbandonSeconds = 120;
const _defaultReconnectSeconds = 5;

int _parsePositiveSeconds(String input, int fallback) {
  final value = int.tryParse(input.trim());
  if (value == null || value <= 0) return fallback;
  return value;
}

typedef HttpClientBuilder = http.Client Function();

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({
    super.key,
    required this.auth,
    required this.ws,
    required this.caps,
    this.httpClientBuilder,
  });

  final AuthService auth;
  final WsService ws;
  final PlatformCaps caps;
  final HttpClientBuilder? httpClientBuilder;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  StreamSubscription? _sub;
  String _log = '';

  final _guestNameCtrl = TextEditingController();

  late final http.Client _http =
      widget.httpClientBuilder?.call() ?? http.Client();

  List<Map<String, Object?>> _matches = const [];
  List<Map<String, Object?>> _activeMatches = const [];

  bool _activeMatchesLoading = false;
  bool _activeMatchesHttpInFlight = false;
  String? _activeMatchesError;
  int? _onlinePlayersEstimate;

  String? _pendingActionId;
  String? _pendingMatchId;

  @override
  void initState() {
    super.initState();

    _guestNameCtrl.text = widget.auth.displayName;

    widget.auth.addListener(_onAuthChanged);
    widget.ws.addListener(_onWsChanged);

    if (widget.auth.isLoggedIn && !widget.auth.isGuest) {
      unawaited(_refreshActiveMatchesHttp());
    }

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
        _activeMatches = const [];
        _onlinePlayersEstimate = null;
        _activeMatchesError = null;
        _activeMatchesLoading = false;
        _pendingActionId = null;
        _pendingMatchId = null;
      });
      return;
    }

    if (!widget.auth.isGuest) {
      unawaited(_refreshActiveMatchesHttp());
    }

    if (widget.ws.state == WsConnectionState.disconnected) {
      unawaited(widget.ws.connect());
    }
  }

  void _onWsChanged() {
    if (!mounted) return;
    if (widget.ws.state == WsConnectionState.connected) {
      _refreshAll();
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
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Joining as: ${widget.auth.displayName}'),
                    const SizedBox(height: 12),
                    const Text('Team (optional):'),
                    const SizedBox(height: 8),
                    SegmentedButton<_TeamChoice>(
                      segments: const [
                        ButtonSegment(
                          value: _TeamChoice.auto,
                          label: Text('Auto'),
                        ),
                        ButtonSegment(
                          value: _TeamChoice.team0,
                          label: Text('Team 0'),
                        ),
                        ButtonSegment(
                          value: _TeamChoice.team1,
                          label: Text('Team 1'),
                        ),
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

  void _refreshAll({bool userInitiated = false}) {
    if (widget.ws.state == WsConnectionState.connected) {
      widget.ws.send(WsInFrame(msg: WsMsg.lobbySnapshotGet()));
      if (widget.auth.isLoggedIn && !widget.auth.isGuest) {
        widget.ws.send(WsInFrame(msg: WsMsg.meActiveMatchesGet()));
      }
    }

    if (widget.auth.isLoggedIn && !widget.auth.isGuest) {
      unawaited(_refreshActiveMatchesHttp(userInitiated: userInitiated));
    }
  }

  Future<void> _refreshActiveMatchesHttp({bool userInitiated = false}) async {
    if (_activeMatchesHttpInFlight) return;
    if (!widget.auth.isLoggedIn || widget.auth.isGuest) return;

    final token = widget.auth.accessToken;
    if (token == null || token.isEmpty) return;

    _activeMatchesHttpInFlight = true;
    if (mounted) {
      setState(() {
        _activeMatchesLoading = true;
        if (userInitiated) {
          _activeMatchesError = null;
        }
      });
    }

    try {
      final uri = Uri.parse('${AppConfig.backendBaseUrl}/v1/matches/active');
      final res = await _http.get(
        uri,
        headers: {
          'authorization': 'Bearer $token',
          'accept': 'application/json',
        },
      );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('HTTP ${res.statusCode}');
      }

      final payload = (jsonDecode(res.body) as Map).cast<String, Object?>();
      final matches = _extractActiveMatches(payload['matches']);

      if (!mounted) return;
      setState(() {
        _activeMatches = matches;
        _activeMatchesError = null;
        _onlinePlayersEstimate = _estimateOnlinePlayers(
          _matches,
          _activeMatches,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _activeMatchesError = 'Failed to fetch resume list (${e.toString()})';
      });
    } finally {
      _activeMatchesHttpInFlight = false;
      if (!mounted) return;
      setState(() {
        _activeMatchesLoading = false;
      });
    }
  }

  Future<void> _showCreateMatchDialog(BuildContext context) async {
    int maxPlayers = 2;
    var teamChoice = _TeamChoice.auto;
    final abandonCtrl = TextEditingController(
      text: _defaultAbandonSeconds.toString(),
    );
    final reconnectCtrl = TextEditingController(
      text: _defaultReconnectSeconds.toString(),
    );

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Create match'),
              content: SingleChildScrollView(
                child: Column(
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
                        ButtonSegment(
                          value: _TeamChoice.auto,
                          label: Text('Auto'),
                        ),
                        ButtonSegment(
                          value: _TeamChoice.team0,
                          label: Text('Team 0'),
                        ),
                        ButtonSegment(
                          value: _TeamChoice.team1,
                          label: Text('Team 1'),
                        ),
                      ],
                      selected: {teamChoice},
                      onSelectionChanged: (set) {
                        setLocalState(() {
                          teamChoice = set.first;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Inactivity sweeps',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: abandonCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Disconnect sweep',
                        helperText:
                            'Disconnected players longer than this are removed.',
                        suffixText: 'sec',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reconnectCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Reconnect grace',
                        helperText: 'Delay before sweeps run after a drop.',
                        suffixText: 'sec',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
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

    final abandonText = abandonCtrl.text;
    final reconnectText = reconnectCtrl.text;

    if (created != true) return;

    final abandonSeconds = _parsePositiveSeconds(
      abandonText,
      _defaultAbandonSeconds,
    );
    final reconnectSeconds = _parsePositiveSeconds(
      reconnectText,
      _defaultReconnectSeconds,
    );

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
          abandonTimeMs: abandonSeconds * 1000,
          reconnectGraceMs: reconnectSeconds * 1000,
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
            SnackBar(
              content: Text('${code ?? 'ERROR'}: ${msg ?? 'request failed'}'),
            ),
          );
        }
        return;

      case 'lobby.snapshot':
        final matches =
            (data['matches'] as List?)
                ?.whereType<Map>()
                .map((m) => m.cast<String, Object?>())
                .toList() ??
            const <Map<String, Object?>>[];
        setState(() {
          _matches = matches;
          _onlinePlayersEstimate = _estimateOnlinePlayers(
            _matches,
            _activeMatches,
          );
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
          _onlinePlayersEstimate = _estimateOnlinePlayers(
            _matches,
            _activeMatches,
          );
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
          _onlinePlayersEstimate = _estimateOnlinePlayers(
            _matches,
            _activeMatches,
          );
        });
        return;

      case 'me.active_matches':
        final matches = _extractActiveMatches(data['matches']);
        setState(() {
          _activeMatches = matches;
          _onlinePlayersEstimate = _estimateOnlinePlayers(
            _matches,
            _activeMatches,
          );
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
    _http.close();
    super.dispose();
  }

  Widget _buildUnauthedBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Welcome', style: Theme.of(context).textTheme.headlineMedium),
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

  Widget _buildActiveMatchesSection(BuildContext context) {
    if (!widget.auth.isLoggedIn || widget.auth.isGuest) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final hasMatches = _activeMatches.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Resume matches', style: theme.textTheme.titleSmall),
            const Spacer(),
            if (_activeMatchesLoading)
              const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            IconButton(
              tooltip: 'Refresh resume list',
              onPressed: _activeMatchesLoading
                  ? null
                  : () => _refreshAll(userInitiated: true),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_activeMatchesError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _activeMatchesError!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        if (!hasMatches)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _activeMatchesLoading
                  ? 'Loading resume list...'
                  : 'No active matches to resume.',
              style: theme.textTheme.bodySmall,
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _activeMatches.length,
            itemBuilder: (context, idx) {
              final summary = _activeMatches[idx];
              final match =
                  (summary['match'] as Map?)?.cast<String, Object?>() ??
                  const <String, Object?>{};
              final me =
                  (summary['me'] as Map?)?.cast<String, Object?>() ??
                  const <String, Object?>{};

              final id = (match['id'] as String?) ?? '<unknown>';
              final phase = (match['phase'] as String?) ?? '?';
              final players =
                  (match['players'] as List?)
                      ?.whereType<Map>()
                      .map((p) => p['name'])
                      .whereType<String>()
                      .toList() ??
                  const <String>[];
              final maxPlayers = _readMaxPlayers(match);
              final spectatorCount = _readSpectatorCount(match);

              final sizeLabel = maxPlayers == null
                  ? ''
                  : ' • ${players.length}/$maxPlayers';
              final spectatorLabel =
                  spectatorCount == null || spectatorCount == 0
                  ? ''
                  : ' • spectators: $spectatorCount';
              final namesLabel = players.isEmpty
                  ? ''
                  : ' • ${players.join(', ')}';

              final ready = me['ready'] == true;
              final team = me['team'];
              final disconnected = me['disconnected_at_ms'] != null;
              final youBits = <String>[];
              if (team is int || team is num) {
                youBits.add('team ${team is num ? team.toInt() : team}');
              }
              youBits.add(ready ? 'ready' : 'not ready');
              if (disconnected) youBits.add('disconnected');
              final youLabel = youBits.isEmpty
                  ? ''
                  : ' • you: ${youBits.join(', ')}';

              return Card(
                child: ListTile(
                  title: Text('Match $id'),
                  subtitle: Text(
                    '$phase$sizeLabel$spectatorLabel$namesLabel$youLabel',
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: () => context.go('/match/$id'),
                    child: const Text('Resume'),
                  ),
                  onTap: () => context.go('/match/$id'),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildLobbyBody(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
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
                      onPressed: () =>
                          unawaited(_showDisplayNameDialog(context)),
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
            if (_onlinePlayersEstimate != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Online players (estimate): ${_onlinePlayersEstimate}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
                      ? () => _refreshAll(userInitiated: true)
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
            if (widget.auth.isLoggedIn && !widget.auth.isGuest) ...[
              _buildActiveMatchesSection(context),
              const SizedBox(height: 12),
            ],
            const Text('Lobby matches:'),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _matches.length,
              itemBuilder: (context, idx) {
                final m = _matches[idx];
                final id = (m['id'] as String?) ?? '<unknown>';
                final phase = (m['phase'] as String?) ?? '?';

                final players =
                    (m['players'] as List?)
                        ?.whereType<Map>()
                        .map((p) => p['name'])
                        .whereType<String>()
                        .toList() ??
                    const <String>[];

                final maxPlayers = _readMaxPlayers(m);
                final needsTeamChoice = (maxPlayers ?? 2) >= 4;
                final spectatorCount = _readSpectatorCount(m);

                final sizeLabel = maxPlayers == null
                    ? ''
                    : ' • ${players.length}/$maxPlayers';
                final spectatorLabel =
                    spectatorCount == null || spectatorCount == 0
                    ? ''
                    : ' • spectators: ${spectatorCount}';
                final namesLabel = players.isEmpty
                    ? ''
                    : ' • ${players.join(', ')}';

                return Card(
                  child: ListTile(
                    title: Text('Match $id'),
                    subtitle: Text(
                      '$phase$sizeLabel$spectatorLabel$namesLabel',
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed:
                              widget.ws.state == WsConnectionState.connected
                              ? () =>
                                    unawaited(_watchMatch(context, matchId: id))
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
