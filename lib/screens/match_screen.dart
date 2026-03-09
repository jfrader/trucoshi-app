import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/pause_models.dart';
import '../services/ws/v2_types.dart';
import '../services/ws/ws_service.dart';
import '../widgets/match_chat_panel.dart';
import '../widgets/pause_banner.dart';
import '../widgets/status_chip.dart';
import '../widgets/team_score_chip.dart';
import '../utils/kick_reason.dart';

class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key, required this.ws, required this.matchId});

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
  bool _showingKickedDialog = false;
  String? _pendingOptionsActionId;
  String? _pendingRematchActionId;
  String? _pendingPauseActionId;
  String? _pendingResumeActionId;
  String? _pendingPauseVoteActionId;
  bool _pauseVoteSubmitting = false;

  @override
  void initState() {
    super.initState();

    widget.ws.addListener(_onWsChanged);

    // Ensure we're connected (no-op if already connected).
    unawaited(widget.ws.connect());

    // Always refresh snapshot on entry.
    if (widget.ws.state == WsConnectionState.connected) {
      widget.ws.send(
        WsInFrame(msg: WsMsg.matchSnapshotGet(matchId: widget.matchId)),
      );
    }

    _sub = widget.ws.incoming.listen(_handleFrame);
  }

  void _onWsChanged() {
    if (!mounted) return;
    if (widget.ws.state == WsConnectionState.connected) {
      widget.ws.send(
        WsInFrame(msg: WsMsg.matchSnapshotGet(matchId: widget.matchId)),
      );
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
      final isRematchResponse =
          _pendingRematchActionId != null &&
          frame.id == _pendingRematchActionId;
      if (matchId != null && matchId != widget.matchId) {
        if (isRematchResponse) {
          final newMatchId = matchId;
          setState(() {
            _pendingRematchActionId = null;
          });
          if (!mounted) return;
          context.go('/match/$newMatchId');
        }
        return;
      }

      final me = (data['me'] as Map?)?.cast<String, Object?>();
      final phase = m['phase'] as String?;
      final prevPhase = _lastPhase;
      final matchedPauseAction =
          _pendingPauseActionId != null && frame.id == _pendingPauseActionId;
      final matchedResumeAction =
          _pendingResumeActionId != null && frame.id == _pendingResumeActionId;
      final matchedPauseVoteAction =
          _pendingPauseVoteActionId != null &&
          frame.id == _pendingPauseVoteActionId;

      setState(() {
        _match = m;
        if (me != null) _me = me;
        _lastPhase = phase ?? _lastPhase;
        if (matchedPauseAction) _pendingPauseActionId = null;
        if (matchedResumeAction) _pendingResumeActionId = null;
        if (matchedPauseVoteAction) _pendingPauseVoteActionId = null;
        _pauseVoteSubmitting = false;
      });

      if (_pendingOptionsActionId != null &&
          frame.id == _pendingOptionsActionId) {
        setState(() {
          _pendingOptionsActionId = null;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Match options updated')),
          );
        }
      }

      if (_pendingRematchActionId != null &&
          frame.id == _pendingRematchActionId) {
        setState(() {
          _pendingRematchActionId = null;
        });
      }

      // When match starts, proactively fetch gameplay snapshot and move to table.
      if (phase == 'started' && _game == null) {
        if (widget.ws.state == WsConnectionState.connected) {
          widget.ws.send(
            WsInFrame(msg: WsMsg.gameSnapshotGet(matchId: widget.matchId)),
          );
        }
      }

      if (phase == 'started' && prevPhase != 'started' && !_navigatedToTable) {
        _navigatedToTable = true;
        if (!mounted) return;
        final router = GoRouter.maybeOf(context);
        router?.go('/table/${widget.matchId}');
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

    if (type == 'match.kicked') {
      final matchId = data['match_id'] as String?;
      if (matchId != widget.matchId) return;
      final reason = data['reason'] as String?;
      _showKickedDialog(reason);
      return;
    }

    if (type == 'match.left') {
      final matchId = data['match_id'] as String?;
      if (matchId != widget.matchId) return;
      _goToLobby();
      return;
    }

    if (type == 'ok') {
      final matchesPause =
          _pendingPauseActionId != null && frame.id == _pendingPauseActionId;
      final matchesResume =
          _pendingResumeActionId != null && frame.id == _pendingResumeActionId;
      final matchesVote =
          _pendingPauseVoteActionId != null &&
          frame.id == _pendingPauseVoteActionId;
      if (matchesPause || matchesResume || matchesVote) {
        setState(() {
          if (matchesPause) _pendingPauseActionId = null;
          if (matchesResume) _pendingResumeActionId = null;
          if (matchesVote) {
            _pendingPauseVoteActionId = null;
            _pauseVoteSubmitting = false;
          }
        });
      }
      return;
    }

    if (type == 'error') {
      final code = data['code'] as String?;
      final msg = data['message'] as String?;
      final isOptionsError =
          _pendingOptionsActionId != null &&
          frame.id == _pendingOptionsActionId;
      final isRematchError =
          _pendingRematchActionId != null &&
          frame.id == _pendingRematchActionId;
      final isPauseError =
          _pendingPauseActionId != null && frame.id == _pendingPauseActionId;
      final isResumeError =
          _pendingResumeActionId != null && frame.id == _pendingResumeActionId;
      final isPauseVoteError =
          _pendingPauseVoteActionId != null &&
          frame.id == _pendingPauseVoteActionId;
      if (isOptionsError) {
        setState(() {
          _pendingOptionsActionId = null;
        });
      }
      if (isRematchError) {
        setState(() {
          _pendingRematchActionId = null;
        });
      }
      if (isPauseError) {
        setState(() {
          _pendingPauseActionId = null;
        });
      }
      if (isResumeError) {
        setState(() {
          _pendingResumeActionId = null;
        });
      }
      if (isPauseVoteError) {
        setState(() {
          _pendingPauseVoteActionId = null;
          _pauseVoteSubmitting = false;
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${code ?? 'ERROR'}: ${msg ?? 'request failed'}'),
        ),
      );
      return;
    }
  }

  Future<void> _showKickedDialog(String? reason) async {
    if (_showingKickedDialog || !mounted) return;
    _showingKickedDialog = true;
    final description = describeKickReason(reason);

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('Removed from match'),
            content: Text(description),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to lobby'),
              ),
            ],
          );
        },
      );
    } finally {
      _showingKickedDialog = false;
      _goToLobby();
    }
  }

  Future<void> _confirmKick({
    required int seatIdx,
    required String displayName,
  }) async {
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove player'),
        content: Text(
          'Remove $displayName from the match? They can rejoin from the lobby afterwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    widget.ws.send(
      WsInFrame(
        msg: WsMsg.matchKick(matchId: widget.matchId, seatIdx: seatIdx),
      ),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Removing $displayName…')));
  }

  Future<void> _showEditOptionsDialog() async {
    final match = _match;
    if (match == null || _pendingOptionsActionId != null) return;

    int maxPlayers = _readMaxPlayers(match) ?? 4;
    int matchPoints = _readMatchPoints(match) ?? 9;
    bool florEnabled = _readFlorEnabled(match) ?? true;
    int faltaEnvido = _readFaltaEnvidoMode(match) ?? 2;
    int turnSeconds = (((_readTurnTimeMs(match) ?? 30000) / 1000).round())
        .clamp(1, 600)
        .toInt();
    int abandonSeconds =
        (((_readAbandonTimeMs(match) ?? 120000) / 1000).round())
            .clamp(1, 600)
            .toInt();
    int reconnectSeconds =
        (((_readReconnectGraceMs(match) ?? 5000) / 1000).round())
            .clamp(1, 60)
            .toInt();

    final matchPointsCtrl = TextEditingController(text: matchPoints.toString());
    final turnCtrl = TextEditingController(text: turnSeconds.toString());
    final abandonCtrl = TextEditingController(text: abandonSeconds.toString());
    final reconnectCtrl = TextEditingController(
      text: reconnectSeconds.toString(),
    );

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setLocalState) {
              return AlertDialog(
                title: const Text('Edit match options'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                        onChanged: (value) {
                          if (value == null) return;
                          setLocalState(() {
                            maxPlayers = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: matchPointsCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Points to win',
                          helperText: '1-15',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        value: florEnabled,
                        onChanged: (v) {
                          setLocalState(() {
                            florEnabled = v;
                          });
                        },
                        title: const Text('Flor enabled'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        value: faltaEnvido,
                        decoration: const InputDecoration(
                          labelText: 'Falta Envido scoring',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 1,
                            child: Text('Two faltas (2× points)'),
                          ),
                          DropdownMenuItem(
                            value: 2,
                            child: Text('One falta (match points)'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setLocalState(() {
                            faltaEnvido = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: turnCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Turn timer',
                          helperText: 'Seconds (1-600)',
                          suffixText: 'sec',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: abandonCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Disconnect sweep',
                          helperText: 'Seconds before AFK removal (1-600)',
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
                          helperText: 'Seconds before sweeps run (1-60)',
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
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (saved == true) {
        final parsedMatchPoints = _parseBoundedInt(
          matchPointsCtrl.text,
          fallback: matchPoints,
          min: 1,
          max: 15,
        );
        final parsedTurnSeconds = _parseBoundedInt(
          turnCtrl.text,
          fallback: turnSeconds,
          min: 1,
          max: 600,
        );
        final parsedAbandonSeconds = _parseBoundedInt(
          abandonCtrl.text,
          fallback: abandonSeconds,
          min: 1,
          max: 600,
        );
        final parsedReconnectSeconds = _parseBoundedInt(
          reconnectCtrl.text,
          fallback: reconnectSeconds,
          min: 1,
          max: 60,
        );

        _submitMatchOptions(
          maxPlayers: maxPlayers,
          matchPoints: parsedMatchPoints,
          flor: florEnabled,
          faltaEnvido: faltaEnvido,
          turnTimeMs: parsedTurnSeconds * 1000,
          abandonTimeMs: parsedAbandonSeconds * 1000,
          reconnectGraceMs: parsedReconnectSeconds * 1000,
        );
      }
    } finally {
      matchPointsCtrl.dispose();
      turnCtrl.dispose();
      abandonCtrl.dispose();
      reconnectCtrl.dispose();
    }
  }

  void _submitMatchOptions({
    required int maxPlayers,
    required int matchPoints,
    required bool flor,
    required int faltaEnvido,
    required int turnTimeMs,
    required int abandonTimeMs,
    required int reconnectGraceMs,
  }) {
    if (!mounted) return;
    final actionId =
        'options-' + DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      _pendingOptionsActionId = actionId;
    });
    widget.ws.send(
      WsInFrame(
        id: actionId,
        msg: WsMsg.matchOptionsSet(
          matchId: widget.matchId,
          maxPlayers: maxPlayers,
          matchPoints: matchPoints,
          flor: flor,
          turnTimeMs: turnTimeMs,
          abandonTimeMs: abandonTimeMs,
          reconnectGraceMs: reconnectGraceMs,
          faltaEnvido: faltaEnvido,
        ),
      ),
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Updating match options…')));
  }

  void _requestRematch() {
    if (!mounted || _pendingRematchActionId != null) return;
    final actionId =
        'rematch-' + DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      _pendingRematchActionId = actionId;
    });
    widget.ws.send(
      WsInFrame(
        id: actionId,
        msg: WsMsg.matchRematch(matchId: widget.matchId),
      ),
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Creating rematch…')));
  }

  void _requestPause() {
    if (!mounted || _pendingPauseActionId != null) return;
    final actionId =
        'pause-' + DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      _pendingPauseActionId = actionId;
    });
    widget.ws.send(
      WsInFrame(
        id: actionId,
        msg: WsMsg.matchPause(matchId: widget.matchId),
      ),
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Requesting pause…')));
  }

  void _requestResume() {
    if (!mounted || _pendingResumeActionId != null) return;
    final actionId =
        'resume-' + DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      _pendingResumeActionId = actionId;
    });
    widget.ws.send(
      WsInFrame(
        id: actionId,
        msg: WsMsg.matchResume(matchId: widget.matchId),
      ),
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Resuming match…')));
  }

  void _submitPauseVote(bool accept) {
    if (!mounted || _pauseVoteSubmitting) return;
    final actionId =
        'pause-vote-' + DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      _pauseVoteSubmitting = true;
      _pendingPauseVoteActionId = actionId;
    });
    widget.ws.send(
      WsInFrame(
        id: actionId,
        msg: WsMsg.matchPauseVote(matchId: widget.matchId, accept: accept),
      ),
    );
  }

  void _goToLobby() {
    if (!mounted) return;
    final router = GoRouter.maybeOf(context);
    router?.go('/lobby');
  }

  @override
  void dispose() {
    widget.ws.removeListener(_onWsChanged);
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final matchPretty = _match == null
        ? '(none yet)'
        : const JsonEncoder.withIndent('  ').convert(_match);
    final gamePretty = _game == null
        ? '(none yet)'
        : const JsonEncoder.withIndent('  ').convert(_game);

    final players =
        (_match?['players'] as List?)
            ?.whereType<Map>()
            .map((p) => p.cast<String, Object?>())
            .toList() ??
        const <Map<String, Object?>>[];

    final spectatorCount = _readSpectatorCount(_match);
    final meSeatIdx = _me?['seat_idx'] as int?;
    final isSpectating = meSeatIdx == null;
    final ownerSeatIdx = _match?['owner_seat_idx'] as int?;
    final phase = _match?['phase'] as String?;
    final myTeamIdx = _readMyTeamIdx(players, meSeatIdx);

    final pauseRequest = readPauseRequest(_match);
    final pendingUnpause = readPendingUnpause(_match);
    final pauseAwaitingSeats = pauseRequest == null
        ? const <PauseAwaitingSeat>[]
        : buildPauseAwaitingSeats(
            request: pauseRequest,
            players: players,
            meSeatIdx: meSeatIdx,
          );
    final requestedByLabel = pauseRequest == null
        ? ''
        : describePauseRequester(pauseRequest, players);
    final awaitingTeamLabel = pauseRequest == null
        ? ''
        : 'Team ${pauseRequest.awaitingTeam}';
    final isAwaitingMember =
        pauseRequest != null &&
        myTeamIdx != null &&
        pauseRequest.awaitingTeam == myTeamIdx;
    final hasAccepted =
        pauseRequest != null &&
        meSeatIdx != null &&
        pauseRequest.acceptedSeatIdxs.contains(meSeatIdx);
    final canVote = pauseRequest != null && phase == 'started';

    final iAmOwner =
        meSeatIdx != null && ownerSeatIdx != null && meSeatIdx == ownerSeatIdx;
    final myReady = (meSeatIdx != null && meSeatIdx < players.length)
        ? (players[meSeatIdx]['ready'] as bool?)
        : null;

    final allReady =
        players.isNotEmpty &&
        players.every((p) => (p['ready'] as bool?) == true);

    final readyCount = players
        .where((p) => (p['ready'] as bool?) == true)
        .length;

    final matchName = (_match?['name'] as String?) ?? widget.matchId;
    final maxPlayers = _readMaxPlayers(_match);
    final matchPoints = _readMatchPoints(_match);
    final faltaEnvidoMode = _readFaltaEnvidoMode(_match);
    final turnTimeMs = _readTurnTimeMs(_match);
    final florEnabled = _readFlorEnabled(_match);
    final abandonTimeMs = _readAbandonTimeMs(_match);
    final reconnectGraceMs = _readReconnectGraceMs(_match);
    final teamPoints = _readTeamPoints(_match);
    final winnerTeamIdx = _readWinnerTeamIdx(_match, _game);

    final canEditOptions = iAmOwner && phase == 'lobby';
    final optionsSaving = _pendingOptionsActionId != null;
    final canSubmitOptionChanges =
        canEditOptions &&
        widget.ws.state == WsConnectionState.connected &&
        !optionsSaving;
    final canRematch = phase == 'finished' && iAmOwner;
    final rematchPending = _pendingRematchActionId != null;
    final canPause = phase == 'started' && iAmOwner && pauseRequest == null;
    final pausePending = _pendingPauseActionId != null;
    final canResume = phase == 'paused' && iAmOwner && pendingUnpause == null;
    final resumePending = _pendingResumeActionId != null;

    final metaChips = <Widget>[];
    if (phase != null) {
      metaChips.add(StatusChip(icon: Icons.timelapse, label: 'phase: $phase'));
    }
    metaChips.add(
      StatusChip(
        icon: Icons.groups,
        label: maxPlayers == null
            ? 'players: ${players.length}'
            : 'players: ${players.length}/$maxPlayers',
      ),
    );
    if (players.isNotEmpty) {
      metaChips.add(
        StatusChip(
          icon: Icons.check_circle,
          label: 'ready: $readyCount/${players.length}',
        ),
      );
    }
    if (isSpectating) {
      metaChips.add(
        StatusChip(
          icon: Icons.visibility,
          label: 'Spectating',
          tone: scheme.primary,
        ),
      );
    }
    if (spectatorCount != null) {
      metaChips.add(
        StatusChip(
          icon: Icons.visibility_outlined,
          label: 'spectators: $spectatorCount',
        ),
      );
    }
    if (ownerSeatIdx != null) {
      metaChips.add(
        StatusChip(icon: Icons.chair, label: 'owner seat: $ownerSeatIdx'),
      );
    }
    if (meSeatIdx != null) {
      metaChips.add(
        StatusChip(icon: Icons.event_seat, label: 'your seat: $meSeatIdx'),
      );
    }

    final optionChips = <Widget>[];
    if (maxPlayers != null) {
      optionChips.add(
        StatusChip(icon: Icons.groups_2, label: 'Max players: $maxPlayers'),
      );
    }
    if (matchPoints != null) {
      optionChips.add(
        StatusChip(icon: Icons.flag, label: 'Points to win: $matchPoints'),
      );
    }
    if (faltaEnvidoMode != null) {
      optionChips.add(
        StatusChip(
          icon: Icons.change_circle,
          label: faltaEnvidoMode == 1
              ? 'Falta Envido: 2× match points'
              : 'Falta Envido: match points',
        ),
      );
    }
    if (florEnabled != null) {
      optionChips.add(
        StatusChip(
          icon: florEnabled
              ? Icons.local_florist
              : Icons.local_florist_outlined,
          label: florEnabled ? 'Flor enabled' : 'Flor disabled',
          tone: florEnabled ? scheme.tertiary : scheme.error,
        ),
      );
    }
    if (turnTimeMs != null) {
      optionChips.add(
        StatusChip(
          icon: Icons.timer,
          label: 'Turn timer: ${_formatTurnTime(turnTimeMs)}',
        ),
      );
    }
    if (abandonTimeMs != null) {
      optionChips.add(
        StatusChip(
          icon: Icons.portable_wifi_off,
          label: 'Disconnect sweep: ${_formatDuration(abandonTimeMs)}',
        ),
      );
    }
    if (reconnectGraceMs != null) {
      optionChips.add(
        StatusChip(
          icon: Icons.restart_alt,
          label: 'Reconnect grace: ${_formatDuration(reconnectGraceMs)}',
        ),
      );
    }

    final children = <Widget>[
      ListenableBuilder(
        listenable: widget.ws,
        builder: (context, _) {
          final extras = <String>[];
          if (widget.ws.serverVersion != null) {
            extras.add('v=${widget.ws.serverVersion}');
          }
          if (widget.ws.sessionId != null) {
            extras.add('sid=${widget.ws.sessionId}');
          }
          if (widget.ws.lastPongRttMs != null) {
            extras.add('rtt=${widget.ws.lastPongRttMs}ms');
          }
          final suffix = extras.isEmpty ? '' : '  •  ${extras.join('  •  ')}';
          final err = widget.ws.lastError;
          final errorSuffix = err == null ? '' : '  •  $err';
          return Text('WS: ${widget.ws.state}$suffix$errorSuffix');
        },
      ),
      const SizedBox(height: 12),
    ];

    if (_match == null) {
      children.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Waiting for match snapshot…',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    } else {
      children.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(matchName, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: metaChips),
                if (teamPoints != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TeamScoreChip(
                          teamIdx: 0,
                          points: teamPoints.length > 0 ? teamPoints[0] : null,
                          highlight: myTeamIdx == 0,
                          winner: winnerTeamIdx == 0,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TeamScoreChip(
                          teamIdx: 1,
                          points: teamPoints.length > 1 ? teamPoints[1] : null,
                          highlight: myTeamIdx == 1,
                          winner: winnerTeamIdx == 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );

      if (pauseRequest != null) {
        children.add(const SizedBox(height: 12));
        children.add(
          PauseRequestBanner(
            requestedByLabel: requestedByLabel,
            awaitingTeamLabel: awaitingTeamLabel,
            awaitingSeats: pauseAwaitingSeats,
            expiresAtMs: pauseRequest.expiresAtMs,
            isAwaitingMember: isAwaitingMember,
            canVote: canVote && widget.ws.state == WsConnectionState.connected,
            hasAccepted: hasAccepted,
            voteSubmitting: _pauseVoteSubmitting,
            onAccept: () => _submitPauseVote(true),
            onDecline: () => _submitPauseVote(false),
          ),
        );
      }
      if (pendingUnpause != null) {
        children.add(const SizedBox(height: 12));
        children.add(
          PendingUnpauseBanner(resumeAtMs: pendingUnpause.resumeAtMs),
        );
      }

      children.add(const SizedBox(height: 12));
      children.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Players', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (players.isEmpty)
                  Text(
                    'No players yet. Waiting for lobby updates…',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  )
                else ...[
                  for (var i = 0; i < players.length; i++) ...[
                    if (i > 0) const Divider(),
                    _PlayerRow(
                      seatIdx: i,
                      name: (players[i]['name'] as String?) ?? 'player',
                      teamLabel: _teamLabel(players[i]['team']),
                      ready: players[i]['ready'] == true,
                      isMe: meSeatIdx == i,
                      isOwner: ownerSeatIdx == i,
                      onKick:
                          (iAmOwner &&
                              meSeatIdx != null &&
                              i != meSeatIdx &&
                              widget.ws.state == WsConnectionState.connected)
                          ? () => _confirmKick(
                              seatIdx: i,
                              displayName:
                                  (players[i]['name'] as String?) ?? 'player',
                            )
                          : null,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      );

      if (optionChips.isNotEmpty) {
        children.add(const SizedBox(height: 12));
        children.add(
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Match options',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: optionChips),
                  if (canEditOptions) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: canSubmitOptionChanges
                            ? () => _showEditOptionsDialog()
                            : null,
                        icon: optionsSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.tune),
                        label: Text(optionsSaving ? 'Saving…' : 'Edit options'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }
    }

    children.add(const SizedBox(height: 12));

    final actionButtons = <Widget>[
      OutlinedButton.icon(
        onPressed: widget.ws.state == WsConnectionState.connected
            ? () {
                widget.ws.send(
                  WsInFrame(
                    msg: WsMsg.matchSnapshotGet(matchId: widget.matchId),
                  ),
                );
              }
            : null,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh match'),
      ),
      OutlinedButton.icon(
        onPressed: widget.ws.state == WsConnectionState.connected
            ? () {
                widget.ws.send(
                  WsInFrame(
                    msg: WsMsg.gameSnapshotGet(matchId: widget.matchId),
                  ),
                );
              }
            : null,
        icon: const Icon(Icons.videogame_asset),
        label: const Text('Refresh game'),
      ),
      OutlinedButton.icon(
        onPressed: () => context.go('/table/${widget.matchId}'),
        icon: const Icon(Icons.table_restaurant),
        label: const Text('Open table'),
      ),
      TextButton.icon(
        onPressed: widget.ws.state == WsConnectionState.connected
            ? () {
                widget.ws.send(
                  WsInFrame(msg: WsMsg.matchLeave(matchId: widget.matchId)),
                );
              }
            : null,
        icon: const Icon(Icons.exit_to_app),
        label: const Text('Leave match'),
      ),
    ];

    if (canPause) {
      actionButtons.insert(
        0,
        FilledButton.icon(
          onPressed:
              pausePending || widget.ws.state != WsConnectionState.connected
              ? null
              : _requestPause,
          icon: pausePending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.pause),
          label: Text(pausePending ? 'Pausing…' : 'Pause match'),
        ),
      );
    }

    if (canResume) {
      actionButtons.insert(
        0,
        FilledButton.icon(
          onPressed:
              resumePending || widget.ws.state != WsConnectionState.connected
              ? null
              : _requestResume,
          icon: resumePending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
          label: Text(resumePending ? 'Resuming…' : 'Resume match'),
        ),
      );
    }

    if (canRematch) {
      actionButtons.insert(
        0,
        FilledButton.icon(
          onPressed:
              rematchPending || widget.ws.state != WsConnectionState.connected
              ? null
              : _requestRematch,
          icon: rematchPending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.replay),
          label: Text(rematchPending ? 'Rematching…' : 'Rematch'),
        ),
      );
    }

    if (myReady != null) {
      actionButtons.insert(
        0,
        FilledButton.icon(
          onPressed: widget.ws.state == WsConnectionState.connected
              ? () {
                  widget.ws.send(
                    WsInFrame(
                      msg: WsMsg.matchReady(
                        matchId: widget.matchId,
                        ready: !(myReady ?? false),
                      ),
                    ),
                  );
                }
              : null,
          icon: Icon(myReady == true ? Icons.remove_done : Icons.check),
          label: Text(myReady == true ? 'Set not ready' : 'Ready up'),
        ),
      );
    }

    if (widget.ws.state == WsConnectionState.connected &&
        phase == 'lobby' &&
        iAmOwner &&
        allReady) {
      actionButtons.insert(
        myReady == null ? 0 : 1,
        FilledButton.tonalIcon(
          onPressed: () {
            widget.ws.send(
              WsInFrame(msg: WsMsg.matchStart(matchId: widget.matchId)),
            );
          },
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start match'),
        ),
      );
    }

    children.add(
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(spacing: 12, runSpacing: 12, children: actionButtons),
        ),
      ),
    );

    children.add(const SizedBox(height: 12));
    children.add(MatchChatPanel(ws: widget.ws, roomId: widget.matchId));

    children.add(const SizedBox(height: 12));
    children.add(_DebugTile(title: 'Match JSON', body: matchPretty));
    children.add(const SizedBox(height: 12));
    children.add(_DebugTile(title: 'Game JSON', body: gamePretty));

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
      body: ListView(padding: const EdgeInsets.all(16), children: children),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.seatIdx,
    required this.name,
    required this.teamLabel,
    required this.ready,
    required this.isMe,
    required this.isOwner,
    this.onKick,
  });

  final int seatIdx;
  final String name;
  final String teamLabel;
  final bool ready;
  final bool isMe;
  final bool isOwner;
  final VoidCallback? onKick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? seatIdx.toString()
        : trimmed.substring(0, 1).toUpperCase();

    final chips = <Widget>[
      if (isMe)
        StatusChip(icon: Icons.person, label: 'You', tone: scheme.primary),
      if (isOwner)
        StatusChip(icon: Icons.star, label: 'Owner', tone: scheme.secondary),
      StatusChip(
        icon: ready ? Icons.check_circle : Icons.hourglass_bottom,
        label: ready ? 'Ready' : 'Not ready',
        tone: ready ? scheme.tertiary : scheme.error,
      ),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: isMe ? scheme.primary : scheme.surfaceVariant,
          foregroundColor: isMe ? scheme.onPrimary : scheme.onSurfaceVariant,
          child: Text(initial),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trimmed.isEmpty ? 'Seat $seatIdx' : trimmed,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Seat $seatIdx • Team $teamLabel',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: chips),
                if (onKick != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onKick,
                      icon: const Icon(Icons.person_remove),
                      label: const Text('Remove player'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DebugTile extends StatelessWidget {
  const _DebugTile({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ExpansionTile(
        title: Text(title),
        children: [
          Container(
            width: double.infinity,
            color: scheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              body,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}

int? _readSpectatorCount(Map<String, Object?>? match) {
  if (match == null) return null;
  final raw = match['spectator_count'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return null;
}

List<int>? _readTeamPoints(Map<String, Object?>? match) {
  if (match == null) return null;
  final raw = match['team_points'];
  if (raw is! List || raw.length < 2) return null;

  final a = raw[0];
  final b = raw[1];
  if (a is! num || b is! num) return null;

  return [a.toInt(), b.toInt()];
}

int? _readMyTeamIdx(List<Map<String, Object?>> players, int? meSeatIdx) {
  if (meSeatIdx == null) return null;
  if (meSeatIdx < 0 || meSeatIdx >= players.length) return null;

  final rawTeam = players[meSeatIdx]['team'];
  if (rawTeam is int) return rawTeam;
  if (rawTeam is num) return rawTeam.toInt();
  if (rawTeam is String) return int.tryParse(rawTeam);
  return null;
}

int? _readWinnerTeamIdx(
  Map<String, Object?>? match,
  Map<String, Object?>? game,
) {
  final matchWinner = match?['winner_team_idx'];
  if (matchWinner is int) return matchWinner;
  if (matchWinner is num) return matchWinner.toInt();
  return _readWinnerTeamIdxFromGame(game);
}

int? _readWinnerTeamIdxFromGame(Map<String, Object?>? game) {
  if (game == null) return null;
  final v = game['winner_team_idx'];
  if (v is int) return v;
  if (v is num) return v.toInt();
  return null;
}

int? _readMaxPlayers(Map<String, Object?>? match) {
  if (match == null) return null;
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

int? _readMatchPoints(Map<String, Object?>? match) {
  if (match == null) return null;
  final raw = match['match_points'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();

  final opts = match['options'];
  if (opts is Map) {
    final v = opts['match_points'];
    if (v is int) return v;
    if (v is num) return v.toInt();
  }
  return null;
}

int? _readAbandonTimeMs(Map<String, Object?>? match) {
  if (match == null) return null;
  final raw = match['abandon_time_ms'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();

  final opts = match['options'];
  if (opts is Map) {
    final v = opts['abandon_time_ms'];
    if (v is int) return v;
    if (v is num) return v.toInt();
  }
  return null;
}

int? _readReconnectGraceMs(Map<String, Object?>? match) {
  if (match == null) return null;
  final raw = match['reconnect_grace_ms'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();

  final opts = match['options'];
  if (opts is Map) {
    final v = opts['reconnect_grace_ms'];
    if (v is int) return v;
    if (v is num) return v.toInt();
  }
  return null;
}

int? _readTurnTimeMs(Map<String, Object?>? match) {
  if (match == null) return null;
  final raw = match['turn_time_ms'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();

  final opts = match['options'];
  if (opts is Map) {
    final v = opts['turn_time_ms'];
    if (v is int) return v;
    if (v is num) return v.toInt();
  }
  return null;
}

bool? _readFlorEnabled(Map<String, Object?>? match) {
  if (match == null) return null;
  final raw = match['flor'];
  if (raw is bool) return raw;

  final opts = match['options'];
  if (opts is Map) {
    final v = opts['flor'];
    if (v is bool) return v;
  }
  return null;
}

int? _readFaltaEnvidoMode(Map<String, Object?>? match) {
  if (match == null) return null;
  final raw = match['falta_envido'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();

  final opts = match['options'];
  if (opts is Map) {
    final v = opts['falta_envido'];
    if (v is int) return v;
    if (v is num) return v.toInt();
  }
  return null;
}

String _formatTurnTime(int ms) {
  return _formatDuration(ms);
}

String _formatDuration(int ms) {
  if (ms <= 0) return 'instant';
  final seconds = (ms / 1000).round();
  final minutes = seconds ~/ 60;
  final remainingSeconds = seconds % 60;
  if (minutes > 0) {
    if (remainingSeconds == 0) {
      return '${minutes}m';
    }
    return '${minutes}m ${remainingSeconds}s';
  }
  return '${seconds}s';
}

String _teamLabel(Object? raw) {
  if (raw is int) return raw.toString();
  if (raw is num) return raw.toInt().toString();
  if (raw is String && raw.isNotEmpty) return raw;
  return '?';
}

int _parseBoundedInt(
  String input, {
  required int fallback,
  int? min,
  int? max,
}) {
  final trimmed = input.trim();
  final value = int.tryParse(trimmed);
  if (value == null) return fallback;
  var result = value;
  if (min != null && result < min) {
    result = min;
  }
  if (max != null && result > max) {
    result = max;
  }
  return result;
}
