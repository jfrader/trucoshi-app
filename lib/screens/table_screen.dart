import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/ws/v2_types.dart';
import '../services/ws/ws_service.dart';
import '../widgets/truco_card.dart';

/// Live table screen backed by WS v2 `match.*` + `game.*`.
///
/// Seating is derived from `match.players[]` ordering, rotated so `me.seat_idx`
/// is always rendered at the bottom.
class TableScreen extends StatefulWidget {
  const TableScreen({
    super.key,
    required this.ws,
    required this.matchId,
  });

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
    widget.ws.send(WsInFrame(msg: WsMsg.matchSnapshotGet(matchId: widget.matchId)));
    widget.ws.send(WsInFrame(msg: WsMsg.gameSnapshotGet(matchId: widget.matchId)));
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

    if (type == 'match.left') {
      final matchId = data['match_id'] as String?;
      if (matchId != null && matchId != widget.matchId) return;
      if (!mounted) return;
      context.go('/lobby');
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
    final match = _match;
    final me = _me;
    final game = _game;

    final players = (match?['players'] as List?)
            ?.whereType<Map>()
            .map((p) => p.cast<String, Object?>())
            .toList() ??
        const <Map<String, Object?>>[];

    final meSeatIdx = me?['seat_idx'] as int?;
    final turnSeatIdx = _readTurnSeatIdx(game);
    final forehandSeatIdx = _readForehandSeatIdx(game);

    final myTeamIdx = _readMyTeamIdx(players, meSeatIdx);
    final teamPoints = _readTeamPoints(match);
    final winnerTeamIdx = _readWinnerTeamIdx(game);

    final myHand = _readCardList(me?['hand']);
    final myCommands = _readStringList(me?['commands']);

    final handState = _readHandState(game);
    final canPlay = meSeatIdx != null && turnSeatIdx != null && meSeatIdx == turnSeatIdx;
    final canPlayCard = canPlay && handState == 'waiting_play';

    return Scaffold(
      appBar: AppBar(
        title: Text('Table ${widget.matchId}'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: widget.ws.state == WsConnectionState.connected ? _refreshAll : null,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Leave match',
            onPressed: widget.ws.state == WsConnectionState.connected
                ? () {
                    widget.ws.send(WsInFrame(msg: WsMsg.matchLeave(matchId: widget.matchId)));
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
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  'phase=${match?['phase'] ?? '?'}'
                  '  hand_state=${handState ?? '?'}'
                  '  turn=${turnSeatIdx?.toString() ?? '?'}'
                  '${forehandSeatIdx == null ? '' : '  forehand=$forehandSeatIdx'}'
                  '${meSeatIdx == null ? '' : '  me=$meSeatIdx'}',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _TeamScoreChip(
                        teamIdx: 0,
                        points: teamPoints?[0],
                        highlight: myTeamIdx == 0,
                        winner: winnerTeamIdx == 0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TeamScoreChip(
                        teamIdx: 1,
                        points: teamPoints?[1],
                        highlight: myTeamIdx == 1,
                        winner: winnerTeamIdx == 1,
                      ),
                    ),
                  ],
                ),
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

                    final playedCards = _readPlayedCards(game);

                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Container(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            child: const Center(
                              child: Text(
                                'TABLE',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                        for (var seatIdx = 0; seatIdx < players.length; seatIdx++)
                          Positioned(
                            left: seatPositions[viewIdxForSeat(seatIdx, players.length)].dx,
                            top: seatPositions[viewIdxForSeat(seatIdx, players.length)].dy,
                            child: _Seat(
                              name: players[seatIdx]['name'] as String? ?? 'player',
                              team: players[seatIdx]['team']?.toString() ?? '?',
                              ready: players[seatIdx]['ready'] == true,
                              isMe: meSeatIdx == seatIdx,
                              isTurn: turnSeatIdx == seatIdx,
                            ),
                          ),
                        for (final pc in playedCards)
                          Positioned(
                            left: cardPositions[
                                    viewIdxForSeat((pc['seat_idx'] as int?) ?? 0, players.length)]
                                .dx,
                            top: cardPositions[
                                    viewIdxForSeat((pc['seat_idx'] as int?) ?? 0, players.length)]
                                .dy,
                            child: _PlayedCard(
                              card: _readCardCode(pc['card']),
                            ),
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
                if (myCommands.isNotEmpty) ...[
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
                        DropdownMenuItem(
                          value: c,
                          child: Text(c),
                        ),
                    ],
                    onChanged: widget.ws.state == WsConnectionState.connected
                        ? (v) {
                            if (v == null) return;

                            widget.ws.send(
                              WsInFrame(
                                msg: WsMsg.gameSay(matchId: widget.matchId, command: v),
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
                if (myHand.isEmpty)
                  const Text('Hand: (not available yet)')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < myHand.length; i++)
                        _HandCard(
                          card: myHand[i],
                          enabled: widget.ws.state == WsConnectionState.connected && canPlayCard,
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
                const SizedBox(height: 8),
                Text(
                  canPlayCard
                      ? 'Your turn.'
                      : canPlay
                          ? 'Waiting: $handState'
                          : 'Waiting for other players…',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
    required this.name,
    required this.team,
    required this.ready,
    required this.isMe,
    required this.isTurn,
  });

  final String name;
  final String team;
  final bool ready;
  final bool isMe;
  final bool isTurn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final baseColor = team == '0' ? scheme.primary : scheme.tertiary;
    final bg = isMe ? scheme.secondaryContainer : baseColor.withOpacity(0.18);

    final border = isTurn ? Border.all(color: scheme.primary, width: 2) : null;

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
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: isMe ? scheme.primary : scheme.secondary,
                foregroundColor: scheme.onPrimary,
                child: Text(name.isEmpty ? '?' : name.substring(0, 1).toUpperCase()),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: isMe ? FontWeight.bold : FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('team $team', style: const TextStyle(fontSize: 12)),
              Text(ready ? 'ready' : '…', style: const TextStyle(fontSize: 12)),
            ],
          ),
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
    return TrucoCardImage(
      card,
      width: 56,
      height: 84,
      elevation: 3,
    );
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

class _TeamScoreChip extends StatelessWidget {
  const _TeamScoreChip({
    required this.teamIdx,
    required this.points,
    required this.highlight,
    required this.winner,
  });

  final int teamIdx;
  final int? points;
  final bool highlight;
  final bool winner;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final base = teamIdx == 0 ? scheme.primary : scheme.tertiary;

    final bg = winner
        ? base.withOpacity(0.25)
        : highlight
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest;

    final border = winner
        ? Border.all(color: base, width: 2)
        : highlight
            ? Border.all(color: scheme.secondary, width: 2)
            : Border.all(color: scheme.outlineVariant);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: border,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              winner ? 'Team $teamIdx • WIN' : 'Team $teamIdx',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
          Text(
            (points ?? 0).toString(),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: base,
            ),
          ),
        ],
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
  Offset polar(double angle, double radius) =>
      Offset(center.dx + math.cos(angle) * radius, center.dy + math.sin(angle) * radius);

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

int? _readTurnSeatIdx(Map<String, Object?>? game) {
  if (game == null) return null;

  final direct = game['turn_seat_idx'];
  if (direct is int) return direct;

  final turn = game['turn'];
  if (turn is Map) {
    final seat = (turn as Map)['seat_idx'];
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
    final state = (hand as Map)['state'];
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

List<Map<String, Object?>> _readPlayedCards(Map<String, Object?>? game) {
  if (game == null) return const <Map<String, Object?>>[];

  final trick = game['trick'];
  if (trick is List) {
    return trick.whereType<Map>().map((e) => e.cast<String, Object?>()).toList();
  }

  final rounds = game['rounds'];
  if (rounds is List && rounds.isNotEmpty) {
    final last = rounds.last;
    if (last is List) {
      return last.whereType<Map>().map((e) => e.cast<String, Object?>()).toList();
    }

    if (last is Map) {
      final cards = (last as Map)['cards'];
      if (cards is List) {
        return cards.whereType<Map>().map((e) => e.cast<String, Object?>()).toList();
      }
    }
  }

  return const <Map<String, Object?>>[];
}

