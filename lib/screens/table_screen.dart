import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/ws/v2_types.dart';
import '../services/ws/ws_service.dart';
import '../widgets/status_chip.dart';
import '../widgets/team_score_chip.dart';
import '../widgets/truco_card.dart';
import '../utils/kick_reason.dart';

/// Live table screen backed by WS v2 `match.*` + `game.*`.
///
/// Seating is derived from `match.players[]` ordering, rotated so `me.seat_idx`
/// is always rendered at the bottom.
class TableScreen extends StatefulWidget {
  const TableScreen({super.key, required this.ws, required this.matchId});

  final WsService ws;
  final String matchId;

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  StreamSubscription? _sub;

  Map<String, Object?>? _match;
  Map<String, Object?>? _me;
  Map<String, Object?>? _game;

  String? _lastError;
  bool _showingKickedDialog = false;

  String? _selectedCommand;

  @override
  void initState() {
    super.initState();

    widget.ws.addListener(_onWsChanged);

    // Table UX: ensure we're connected (no-op if already connected).
    unawaited(widget.ws.connect());

    if (widget.ws.state == WsConnectionState.connected) {
      _refreshAll();
    }

    _sub = widget.ws.incoming.listen(_handleFrame);
  }

  void _onWsChanged() {
    if (!mounted) return;

    if (widget.ws.state == WsConnectionState.connected) {
      _refreshAll();
    }
  }

  void _refreshAll() {
    widget.ws.send(
      WsInFrame(msg: WsMsg.matchSnapshotGet(matchId: widget.matchId)),
    );
    widget.ws.send(
      WsInFrame(msg: WsMsg.gameSnapshotGet(matchId: widget.matchId)),
    );
  }

  void _handleFrame(WsOutFrame frame) {
    final type = frame.msg.type;
    final data = frame.msg.data;

    if (type == 'error') {
      final code = data?['code'] as String?;
      final msg = data?['message'] as String?;
      setState(() {
        _lastError = '${code ?? 'ERROR'}: ${msg ?? 'request failed'}';
      });
      return;
    }

    if (data == null) return;

    if (type == 'match.snapshot' || type == 'match.update') {
      final match = (data['match'] as Map?)?.cast<String, Object?>();
      if (match == null) return;

      final matchId = match['id'] as String?;
      if (matchId != null && matchId != widget.matchId) return;

      final me = (data['me'] as Map?)?.cast<String, Object?>();

      setState(() {
        _match = match;
        if (me != null) _me = me;
      });

      return;
    }

    if (type == 'game.snapshot' || type == 'game.update') {
      final matchId = data['match_id'] as String?;
      if (matchId != null && matchId != widget.matchId) return;

      final game = (data['game'] as Map?)?.cast<String, Object?>();
      if (game == null) return;

      final me = (data['me'] as Map?)?.cast<String, Object?>();

      setState(() {
        _game = game;
        if (me != null) _me = me;
      });

      return;
    }

    if (type == 'match.kicked') {
      final matchId = data['match_id'] as String?;
      if (matchId != null && matchId != widget.matchId) return;
      final reason = data['reason'] as String?;
      _showKickedDialog(reason);
      return;
    }

    if (type == 'match.left') {
      final matchId = data['match_id'] as String?;
      if (matchId != null && matchId != widget.matchId) return;
      _goToLobby();
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
        builder: (context) => AlertDialog(
          title: const Text('Removed from match'),
          content: Text(description),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to lobby'),
            ),
          ],
        ),
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
    final match = _match;
    final me = _me;
    final game = _game;

    final players =
        (match?['players'] as List?)
            ?.whereType<Map>()
            .map((p) => p.cast<String, Object?>())
            .toList() ??
        const <Map<String, Object?>>[];

    final spectatorCount = _readSpectatorCount(match);
    final meSeatIdx = me?['seat_idx'] as int?;
    final isSpectating = meSeatIdx == null;
    final turnSeatIdx = _readTurnSeatIdx(game);
    final forehandSeatIdx = _readForehandSeatIdx(game);

    final myTeamIdx = _readMyTeamIdx(players, meSeatIdx);
    final teamPoints = _readTeamPoints(match);
    final winnerTeamIdx = _readWinnerTeamIdx(game);

    final myHand = _readCardList(me?['hand']);
    final myUsed = _readCardList(me?['used']);
    final myCommands = _readStringList(me?['commands']);

    final handState = _readHandState(game);
    final roundInfo = _readRoundInfo(game);

    final canPlay =
        meSeatIdx != null && turnSeatIdx != null && meSeatIdx == turnSeatIdx;
    final canPlayCard = canPlay && handState == 'waiting_play';
    final statusText = isSpectating
        ? 'Spectating: live view only.'
        : canPlayCard
        ? 'Your turn.'
        : canPlay
        ? 'Waiting: ${handState ?? '?'}'
        : 'Waiting for other players…';
    final ownerSeatIdx = _readOwnerSeatIdx(match);
    final bool iAmOwner =
        meSeatIdx != null && ownerSeatIdx != null && meSeatIdx == ownerSeatIdx;
    final wsConnected = widget.ws.state == WsConnectionState.connected;

    return Scaffold(
      appBar: AppBar(
        title: Text('Table ${widget.matchId}'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: widget.ws.state == WsConnectionState.connected
                ? _refreshAll
                : null,
            icon: const Icon(Icons.refresh),
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListenableBuilder(
                  listenable: widget.ws,
                  builder: (context, _) {
                    return Text(
                      'WS: ${widget.ws.state}'
                      '${widget.ws.lastError == null ? '' : '  •  ${widget.ws.lastError}'}',
                    );
                  },
                ),
                if (_lastError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _lastError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  'phase=${match?['phase'] ?? '?'}'
                  '  hand_state=${handState ?? '?'}'
                  '${roundInfo == null ? '' : '  round=${roundInfo.currentRound}/${roundInfo.totalRounds}'}'
                  '  turn=${turnSeatIdx?.toString() ?? '?'}'
                  '${forehandSeatIdx == null ? '' : '  forehand=$forehandSeatIdx'}'
                  '${meSeatIdx == null ? '' : '  me=$meSeatIdx'}',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TeamScoreChip(
                        teamIdx: 0,
                        points: teamPoints?[0],
                        highlight: myTeamIdx == 0,
                        winner: winnerTeamIdx == 0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TeamScoreChip(
                        teamIdx: 1,
                        points: teamPoints?[1],
                        highlight: myTeamIdx == 1,
                        winner: winnerTeamIdx == 1,
                      ),
                    ),
                  ],
                ),
                if (isSpectating || (spectatorCount ?? 0) > 0) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (isSpectating)
                        const StatusChip(
                          icon: Icons.visibility,
                          label: 'Spectating',
                        ),
                      if (spectatorCount != null)
                        StatusChip(
                          icon: Icons.visibility_outlined,
                          label: 'spectators: $spectatorCount',
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final size = Size(c.maxWidth, c.maxHeight);
                    final seatPositions = _seatPositions(players.length, size);
                    final cardPositions = _cardPositions(players.length, size);

                    final rotationOffset = meSeatIdx ?? 0;

                    int viewIdxForSeat(int seatIdx, int n) {
                      if (n == 0) return 0;
                      final raw = seatIdx - rotationOffset;
                      return ((raw % n) + n) % n;
                    }

                    final playedCards =
                        roundInfo?.cards ?? const <Map<String, Object?>>[];

                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Container(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            child: const Center(
                              child: Text(
                                'TABLE',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                        for (
                          var seatIdx = 0;
                          seatIdx < players.length;
                          seatIdx++
                        )
                          (() {
                            final viewIdx = viewIdxForSeat(
                              seatIdx,
                              players.length,
                            );
                            final seatPos = seatPositions[viewIdx];
                            final seatName =
                                (players[seatIdx]['name'] as String?) ??
                                'player';
                            final isSeatOwner = ownerSeatIdx == seatIdx;
                            final canKickSeat =
                                wsConnected && iAmOwner && seatIdx != meSeatIdx;
                            final onRemove = canKickSeat
                                ? () => _confirmKick(
                                    seatIdx: seatIdx,
                                    displayName: seatName,
                                  )
                                : null;

                            return Positioned(
                              left: seatPos.dx,
                              top: seatPos.dy,
                              child: _Seat(
                                seatIdx: seatIdx,
                                name: seatName,
                                team:
                                    players[seatIdx]['team']?.toString() ?? '?',
                                ready: players[seatIdx]['ready'] == true,
                                isMe: meSeatIdx == seatIdx,
                                isTurn: turnSeatIdx == seatIdx,
                                isOwner: isSeatOwner,
                                onRemove: onRemove,
                              ),
                            );
                          })(),
                        for (final pc in playedCards)
                          Positioned(
                            left:
                                cardPositions[viewIdxForSeat(
                                      (pc['seat_idx'] as int?) ?? 0,
                                      players.length,
                                    )]
                                    .dx,
                            top:
                                cardPositions[viewIdxForSeat(
                                      (pc['seat_idx'] as int?) ?? 0,
                                      players.length,
                                    )]
                                    .dy,
                            child: _PlayedCard(card: _readCardCode(pc['card'])),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!isSpectating && myCommands.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    value: myCommands.contains(_selectedCommand)
                        ? _selectedCommand
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Commands',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final c in myCommands)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: widget.ws.state == WsConnectionState.connected
                        ? (v) {
                            if (v == null) return;

                            widget.ws.send(
                              WsInFrame(
                                msg: WsMsg.gameSay(
                                  matchId: widget.matchId,
                                  command: v,
                                ),
                              ),
                            );

                            // Keep the dropdown ready for the next command.
                            setState(() {
                              _selectedCommand = null;
                            });
                          }
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
                if (isSpectating)
                  Text(
                    'Spectating: hands and commands are hidden.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                else if (myHand.isEmpty)
                  const Text('Hand: (not available yet)')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < myHand.length; i++)
                        _HandCard(
                          card: myHand[i],
                          enabled:
                              widget.ws.state == WsConnectionState.connected &&
                              canPlayCard,
                          onPlay: () {
                            widget.ws.send(
                              WsInFrame(
                                msg: WsMsg.gamePlayCard(
                                  matchId: widget.matchId,
                                  cardIdx: i,
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                if (!isSpectating && myUsed.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Used:',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in myUsed)
                        TrucoCardImage(c, width: 40, height: 60, elevation: 1),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  statusText,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Seat extends StatelessWidget {
  const _Seat({
    required this.seatIdx,
    required this.name,
    required this.team,
    required this.ready,
    required this.isMe,
    required this.isTurn,
    required this.isOwner,
    this.onRemove,
  });

  final int seatIdx;
  final String name;
  final String team;
  final bool ready;
  final bool isMe;
  final bool isTurn;
  final bool isOwner;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final baseColor = team == '0' ? scheme.primary : scheme.tertiary;
    final bg = isMe ? scheme.secondaryContainer : baseColor.withOpacity(0.18);

    final border = isTurn ? Border.all(color: scheme.primary, width: 2) : null;

    final trimmed = name.trim();
    final displayName = trimmed.isEmpty ? 'Seat $seatIdx' : trimmed;

    return Container(
      width: 112,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: border,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: isMe ? scheme.primary : scheme.secondary,
                foregroundColor: scheme.onPrimary,
                child: Text(
                  displayName.isEmpty
                      ? '?'
                      : displayName.substring(0, 1).toUpperCase(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isMe
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isOwner)
                          Icon(Icons.star, size: 16, color: scheme.secondary),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        Text(
                          'team $team',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          ready ? 'ready' : '…',
                          style: TextStyle(
                            fontSize: 12,
                            color: ready
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onRemove != null) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                key: ValueKey('seat-$seatIdx-remove'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: onRemove,
                icon: const Icon(Icons.person_remove, size: 16),
                label: const Text('Remove', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlayedCard extends StatelessWidget {
  const _PlayedCard({required this.card});

  final String card;

  @override
  Widget build(BuildContext context) {
    return TrucoCardImage(card, width: 56, height: 84, elevation: 3);
  }
}

class _HandCard extends StatelessWidget {
  const _HandCard({
    required this.card,
    required this.enabled,
    required this.onPlay,
  });

  final String card;
  final bool enabled;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onPlay : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: TrucoCardImage(
          card,
          width: 64,
          height: 96,
          elevation: enabled ? 4 : 1,
        ),
      ),
    );
  }
}

/// Returns top-left coordinates for each seat, where seat[0] is bottom.
///
/// Supports 2/4/6 players.
List<Offset> _seatPositions(int n, Size size) {
  final w = size.width;
  final h = size.height;

  final bottom = Offset(w * 0.5, h * 0.84);
  final top = Offset(w * 0.5, h * 0.06);
  final left = Offset(w * 0.06, h * 0.46);
  final right = Offset(w * 0.94, h * 0.46);

  final topLeft = Offset(w * 0.18, h * 0.14);
  final topRight = Offset(w * 0.82, h * 0.14);
  final bottomLeft = Offset(w * 0.18, h * 0.78);
  final bottomRight = Offset(w * 0.82, h * 0.78);

  const seatSize = Size(112, 70);
  Offset tl(Offset center) =>
      Offset(center.dx - seatSize.width / 2, center.dy - seatSize.height / 2);

  switch (n) {
    case 2:
      return [tl(bottom), tl(top)];
    case 4:
      return [tl(bottom), tl(left), tl(top), tl(right)];
    case 6:
      return [
        tl(bottom),
        tl(bottomLeft),
        tl(topLeft),
        tl(top),
        tl(topRight),
        tl(bottomRight),
      ];
    default:
      return List.filled(n, tl(bottom));
  }
}

/// Returns top-left coordinates for played card labels, where index 0 is bottom.
List<Offset> _cardPositions(int n, Size size) {
  final w = size.width;
  final h = size.height;

  final center = Offset(w * 0.5, h * 0.50);

  // Slightly different radial placement than seats.
  Offset polar(double angle, double radius) => Offset(
    center.dx + math.cos(angle) * radius,
    center.dy + math.sin(angle) * radius,
  );

  const cardSize = Size(56, 84);
  Offset tl(Offset center) =>
      Offset(center.dx - cardSize.width / 2, center.dy - cardSize.height / 2);

  if (n == 2) {
    return [
      tl(polar(math.pi / 2, h * 0.10)),
      tl(polar(-math.pi / 2, h * 0.10)),
    ];
  }

  if (n == 4) {
    return [
      tl(polar(math.pi / 2, h * 0.12)),
      tl(polar(math.pi, w * 0.12)),
      tl(polar(-math.pi / 2, h * 0.12)),
      tl(polar(0, w * 0.12)),
    ];
  }

  if (n == 6) {
    return [
      tl(polar(math.pi / 2, h * 0.14)),
      tl(polar(math.pi * 3 / 4, math.min(w, h) * 0.16)),
      tl(polar(math.pi * 5 / 4, math.min(w, h) * 0.16)),
      tl(polar(-math.pi / 2, h * 0.14)),
      tl(polar(-math.pi * 1 / 4, math.min(w, h) * 0.16)),
      tl(polar(math.pi * 1 / 4, math.min(w, h) * 0.16)),
    ];
  }

  return List.filled(n, tl(center));
}

class _RoundInfo {
  const _RoundInfo({
    required this.currentRound,
    required this.totalRounds,
    required this.cards,
  });

  final int currentRound;
  final int totalRounds;
  final List<Map<String, Object?>> cards;
}

_RoundInfo? _readRoundInfo(Map<String, Object?>? game) {
  if (game == null) return null;

  final raw = game['rounds'];
  if (raw is! List) return null;

  final totalRounds = raw.length;
  if (totalRounds == 0) return null;

  // Find the last non-empty round; when all are empty, use the last one.
  var currentRoundIdx = totalRounds - 1;
  for (var i = totalRounds - 1; i >= 0; i--) {
    final r = raw[i];
    if (r is List && r.isNotEmpty) {
      currentRoundIdx = i;
      break;
    }
  }

  final current = raw[currentRoundIdx];
  final cards = current is List
      ? current.whereType<Map<String, Object?>>().toList()
      : const <Map<String, Object?>>[];

  return _RoundInfo(
    currentRound: currentRoundIdx + 1,
    totalRounds: totalRounds,
    cards: cards,
  );
}

int? _readTurnSeatIdx(Map<String, Object?>? game) {
  if (game == null) return null;

  final direct = game['turn_seat_idx'];
  if (direct is int) return direct;

  final turn = game['turn'];
  if (turn is Map) {
    final seat = turn['seat_idx'];
    if (seat is int) return seat;
  }

  return null;
}

String? _readHandState(Map<String, Object?>? game) {
  if (game == null) return null;
  final direct = game['hand_state'];
  if (direct is String) return direct;

  final hand = game['hand'];
  if (hand is Map) {
    final state = hand['state'];
    if (state is String) return state;
  }

  return null;
}

int? _readForehandSeatIdx(Map<String, Object?>? game) {
  if (game == null) return null;
  final v = game['forehand_seat_idx'];
  return v is int ? v : null;
}

int? _readWinnerTeamIdx(Map<String, Object?>? game) {
  if (game == null) return null;
  final v = game['winner_team_idx'];
  return v is int ? v : null;
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

List<String> _readStringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return raw.whereType<String>().toList();
}

List<String> _readCardList(Object? raw) {
  if (raw is! List) return const <String>[];

  final out = <String>[];
  for (final e in raw) {
    final code = _readCardCode(e).trim();
    if (code.isEmpty) continue;
    out.add(code);
  }
  return out;
}

String _readCardCode(Object? raw) {
  if (raw == null) return '';
  if (raw is String) return raw;

  if (raw is Map) {
    final m = raw.cast<Object?, Object?>();

    final code = m['code'];
    if (code is String) return code;

    final id = m['id'];
    if (id is String) return id;

    final card = m['card'];
    if (card != null) return _readCardCode(card);
  }

  return raw.toString();
}

int? _readOwnerSeatIdx(Map<String, Object?>? match) {
  if (match == null) return null;
  final raw = match['owner_seat_idx'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return null;
}

int? _readSpectatorCount(Map<String, Object?>? match) {
  if (match == null) return null;
  final raw = match['spectator_count'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return null;
}
