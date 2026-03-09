import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'auth_service.dart';

abstract class StatsRepository {
  Future<LeaderboardPage> fetchLeaderboard({
    int limit = 25,
    int? offset,
    int minFinished = 5,
  });

  Future<PlayerProfile> fetchPlayerProfile(
    int userId, {
    int limit = 20,
    int? offset,
  });

  Future<MatchHistory> fetchMatchHistory(
    String matchId, {
    int limit = 200,
    int? afterSeq,
  });

  @mustCallSuper
  void dispose() {}
}

class HttpStatsRepository implements StatsRepository {
  HttpStatsRepository({required this.auth, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final AuthService auth;
  final http.Client _http;

  @override
  void dispose() {
    _http.close();
  }

  @override
  Future<LeaderboardPage> fetchLeaderboard({
    int limit = 25,
    int? offset,
    int minFinished = 5,
  }) async {
    final query = <String, String>{
      'limit': limit.toString(),
      'min_finished': minFinished.toString(),
    };
    if (offset != null) {
      query['offset'] = offset.toString();
    }

    final uri = Uri.parse(
      '${AppConfig.backendBaseUrl}/v1/stats/leaderboard',
    ).replace(queryParameters: query);
    final res = await _http.get(uri, headers: _headers());
    _ensureOk(res);

    final json = _decode(res.body) as Map<String, Object?>;
    final entries =
        (json['entries'] as List?)
            ?.map(_decodeLeaderboardEntry)
            .whereType<LeaderboardEntry>()
            .toList() ??
        const <LeaderboardEntry>[];
    final nextOffset = json['next_offset'];

    return LeaderboardPage(
      entries: entries,
      nextOffset: nextOffset is int
          ? nextOffset
          : nextOffset is num
          ? nextOffset.toInt()
          : null,
    );
  }

  @override
  Future<PlayerProfile> fetchPlayerProfile(
    int userId, {
    int limit = 20,
    int? offset,
  }) async {
    final query = <String, String>{'limit': limit.toString()};
    if (offset != null) {
      query['offset'] = offset.toString();
    }

    final uri = Uri.parse(
      '${AppConfig.backendBaseUrl}/v1/stats/players/$userId',
    ).replace(queryParameters: query);
    final res = await _http.get(uri, headers: _headers());
    _ensureOk(res);

    final json = _decode(res.body) as Map<String, Object?>;
    final userJson = json['user'];
    final totalsJson = json['totals'];
    final matchesJson = json['recent_matches'];

    return PlayerProfile(
      user:
          _decodePlayerProfileUser(userJson) ??
          const PlayerProfileUser(id: 0, name: 'unknown', createdAt: null),
      totals:
          _decodePlayerTotals(totalsJson) ?? const PlayerProfileTotals.empty(),
      recentMatches:
          _decodePlayerMatches(matchesJson) ?? const <PlayerMatchSummary>[],
      nextOffset: _readInt(json['next_offset']),
    );
  }

  @override
  Future<MatchHistory> fetchMatchHistory(
    String matchId, {
    int limit = 200,
    int? afterSeq,
  }) async {
    final query = <String, String>{'limit': limit.toString()};
    if (afterSeq != null) {
      query['after_seq'] = afterSeq.toString();
    }

    final uri = Uri.parse(
      '${AppConfig.backendBaseUrl}/v1/history/matches/$matchId',
    ).replace(queryParameters: query);
    final res = await _http.get(uri, headers: _headers());
    _ensureOk(res);

    final json = _decode(res.body) as Map<String, Object?>;

    return MatchHistory(
      id: _readInt(json['id']) ?? 0,
      wsMatchId: json['ws_match_id'] as String?,
      createdAt: _readDate(json['created_at']),
      finishedAt: _readDate(json['finished_at']),
      serverVersion: json['server_version'] as String?,
      protocolVersion: _readInt(json['protocol_version']),
      rngSeed: _readInt(json['rng_seed']),
      options: _castMap(json['options']) ?? const <String, Object?>{},
      players:
          _decodeHistoryPlayers(json['players']) ??
          const <MatchHistoryPlayer>[],
      events:
          _decodeHistoryEvents(json['events']) ?? const <MatchHistoryEvent>[],
      nextAfterSeq: _readInt(json['next_after_seq']),
    );
  }

  Map<String, String> _headers() {
    final headers = <String, String>{'accept': 'application/json'};

    final token = auth.accessToken;
    if (token != null && token.isNotEmpty && !auth.isGuest) {
      headers['authorization'] = 'Bearer $token';
    }
    return headers;
  }

  void _ensureOk(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw StatsApiException(res.statusCode, res.body);
  }

  Object? _decode(String body) {
    return jsonDecode(body);
  }
}

class StatsApiException implements Exception {
  StatsApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'StatsApiException($statusCode): $body';
}

class LeaderboardPage {
  const LeaderboardPage({required this.entries, this.nextOffset});

  final List<LeaderboardEntry> entries;
  final int? nextOffset;

  bool get hasMore => nextOffset != null;
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.twitterHandle,
    required this.matchesPlayed,
    required this.matchesFinished,
    required this.matchesWon,
    required this.winRate,
    required this.pointsFor,
    required this.pointsAgainst,
    required this.pointsDiff,
    this.lastPlayedAt,
  });

  final int rank;
  final int userId;
  final String name;
  final String? avatarUrl;
  final String? twitterHandle;
  final int matchesPlayed;
  final int matchesFinished;
  final int matchesWon;
  final double winRate;
  final int pointsFor;
  final int pointsAgainst;
  final int pointsDiff;
  final DateTime? lastPlayedAt;
}

class PlayerProfile {
  const PlayerProfile({
    required this.user,
    required this.totals,
    required this.recentMatches,
    this.nextOffset,
  });

  final PlayerProfileUser user;
  final PlayerProfileTotals totals;
  final List<PlayerMatchSummary> recentMatches;
  final int? nextOffset;

  bool get hasMore => nextOffset != null;
}

class PlayerProfileUser {
  const PlayerProfileUser({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.twitterHandle,
    this.createdAt,
  });

  final int id;
  final String name;
  final String? avatarUrl;
  final String? twitterHandle;
  final DateTime? createdAt;
}

@immutable
class PlayerProfileTotals {
  const PlayerProfileTotals({
    required this.matchesPlayed,
    required this.matchesFinished,
    required this.matchesWon,
    required this.winRate,
    required this.pointsFor,
    required this.pointsAgainst,
    required this.pointsDiff,
    this.lastPlayedAt,
  });

  const PlayerProfileTotals.empty()
    : matchesPlayed = 0,
      matchesFinished = 0,
      matchesWon = 0,
      winRate = 0,
      pointsFor = 0,
      pointsAgainst = 0,
      pointsDiff = 0,
      lastPlayedAt = null;

  final int matchesPlayed;
  final int matchesFinished;
  final int matchesWon;
  final double winRate;
  final int pointsFor;
  final int pointsAgainst;
  final int pointsDiff;
  final DateTime? lastPlayedAt;
}

class PlayerMatchSummary {
  const PlayerMatchSummary({
    required this.matchId,
    this.wsMatchId,
    this.createdAt,
    this.finishedAt,
    required this.seatIdx,
    required this.teamIdx,
    this.matchOptions,
    this.teamPoints,
    this.pointsFor,
    this.pointsAgainst,
    this.finishReason,
    required this.outcome,
  });

  final int matchId;
  final String? wsMatchId;
  final DateTime? createdAt;
  final DateTime? finishedAt;
  final int seatIdx;
  final int teamIdx;
  final Map<String, Object?>? matchOptions;
  final List<int>? teamPoints;
  final int? pointsFor;
  final int? pointsAgainst;
  final String? finishReason;
  final PlayerMatchOutcome outcome;

  String get displayMatchId => wsMatchId ?? matchId.toString();
}

enum PlayerMatchOutcome { win, loss, inProgress }

class MatchHistory {
  const MatchHistory({
    required this.id,
    this.wsMatchId,
    this.createdAt,
    this.finishedAt,
    this.serverVersion,
    this.protocolVersion,
    this.rngSeed,
    required this.options,
    required this.players,
    required this.events,
    this.nextAfterSeq,
  });

  final int id;
  final String? wsMatchId;
  final DateTime? createdAt;
  final DateTime? finishedAt;
  final String? serverVersion;
  final int? protocolVersion;
  final int? rngSeed;
  final Map<String, Object?> options;
  final List<MatchHistoryPlayer> players;
  final List<MatchHistoryEvent> events;
  final int? nextAfterSeq;

  bool get hasMoreEvents => nextAfterSeq != null;
}

class MatchHistoryPlayer {
  const MatchHistoryPlayer({
    required this.seatIdx,
    required this.teamIdx,
    this.userId,
    this.displayName,
    this.createdAt,
  });

  final int seatIdx;
  final int teamIdx;
  final int? userId;
  final String? displayName;
  final DateTime? createdAt;
}

class MatchHistoryEvent {
  const MatchHistoryEvent({
    required this.id,
    required this.seq,
    this.createdAt,
    this.actorSeatIdx,
    this.actorUserId,
    required this.type,
    required this.data,
  });

  final int id;
  final int seq;
  final DateTime? createdAt;
  final int? actorSeatIdx;
  final int? actorUserId;
  final String type;
  final Map<String, Object?> data;
}

LeaderboardEntry? _decodeLeaderboardEntry(Object? raw) {
  if (raw is! Map) return null;
  final map = raw.cast<String, Object?>();
  return LeaderboardEntry(
    rank: _readInt(map['rank']) ?? 0,
    userId: _readInt(map['user_id']) ?? 0,
    name: (map['name'] as String?) ?? 'Unknown',
    avatarUrl: map['avatar_url'] as String?,
    twitterHandle: map['twitter_handle'] as String?,
    matchesPlayed: _readInt(map['matches_played']) ?? 0,
    matchesFinished: _readInt(map['matches_finished']) ?? 0,
    matchesWon: _readInt(map['matches_won']) ?? 0,
    winRate: _readDouble(map['win_rate']) ?? 0,
    pointsFor: _readInt(map['points_for']) ?? 0,
    pointsAgainst: _readInt(map['points_against']) ?? 0,
    pointsDiff: _readInt(map['points_diff']) ?? 0,
    lastPlayedAt: _readDate(map['last_played_at']),
  );
}

PlayerProfileUser? _decodePlayerProfileUser(Object? raw) {
  if (raw is! Map) return null;
  final map = raw.cast<String, Object?>();
  return PlayerProfileUser(
    id: _readInt(map['id']) ?? 0,
    name: (map['name'] as String?) ?? 'Unknown',
    avatarUrl: map['avatar_url'] as String?,
    twitterHandle: map['twitter_handle'] as String?,
    createdAt: _readDate(map['created_at']),
  );
}

PlayerProfileTotals? _decodePlayerTotals(Object? raw) {
  if (raw is! Map) return null;
  final map = raw.cast<String, Object?>();
  return PlayerProfileTotals(
    matchesPlayed: _readInt(map['matches_played']) ?? 0,
    matchesFinished: _readInt(map['matches_finished']) ?? 0,
    matchesWon: _readInt(map['matches_won']) ?? 0,
    winRate: _readDouble(map['win_rate']) ?? 0,
    pointsFor: _readInt(map['points_for']) ?? 0,
    pointsAgainst: _readInt(map['points_against']) ?? 0,
    pointsDiff: _readInt(map['points_diff']) ?? 0,
    lastPlayedAt: _readDate(map['last_played_at']),
  );
}

List<PlayerMatchSummary>? _decodePlayerMatches(Object? raw) {
  if (raw is! List) return null;
  return raw.map(_decodePlayerMatch).whereType<PlayerMatchSummary>().toList();
}

PlayerMatchSummary? _decodePlayerMatch(Object? raw) {
  if (raw is! Map) return null;
  final map = raw.cast<String, Object?>();
  return PlayerMatchSummary(
    matchId: _readInt(map['match_id']) ?? 0,
    wsMatchId: map['ws_match_id'] as String?,
    createdAt: _readDate(map['created_at']),
    finishedAt: _readDate(map['finished_at']),
    seatIdx: _readInt(map['seat_idx']) ?? 0,
    teamIdx: _readInt(map['team_idx']) ?? 0,
    matchOptions: _castMap(map['match_options']),
    teamPoints: _castIntList(map['team_points']),
    pointsFor: _readInt(map['points_for']),
    pointsAgainst: _readInt(map['points_against']),
    finishReason: map['finish_reason'] as String?,
    outcome: _decodePlayerMatchOutcome(map['outcome']),
  );
}

PlayerMatchOutcome _decodePlayerMatchOutcome(Object? raw) {
  switch (raw) {
    case 'win':
    case 'Win':
      return PlayerMatchOutcome.win;
    case 'loss':
    case 'Loss':
      return PlayerMatchOutcome.loss;
    default:
      return PlayerMatchOutcome.inProgress;
  }
}

List<MatchHistoryPlayer>? _decodeHistoryPlayers(Object? raw) {
  if (raw is! List) return null;
  return raw.map(_decodeHistoryPlayer).whereType<MatchHistoryPlayer>().toList();
}

MatchHistoryPlayer? _decodeHistoryPlayer(Object? raw) {
  if (raw is! Map) return null;
  final map = raw.cast<String, Object?>();
  return MatchHistoryPlayer(
    seatIdx: _readInt(map['seat_idx']) ?? 0,
    teamIdx: _readInt(map['team_idx']) ?? 0,
    userId: _readInt(map['user_id']),
    displayName: map['display_name'] as String?,
    createdAt: _readDate(map['created_at']),
  );
}

List<MatchHistoryEvent>? _decodeHistoryEvents(Object? raw) {
  if (raw is! List) return null;
  return raw.map(_decodeHistoryEvent).whereType<MatchHistoryEvent>().toList();
}

MatchHistoryEvent? _decodeHistoryEvent(Object? raw) {
  if (raw is! Map) return null;
  final map = raw.cast<String, Object?>();
  return MatchHistoryEvent(
    id: _readInt(map['id']) ?? 0,
    seq: _readInt(map['seq']) ?? 0,
    createdAt: _readDate(map['created_at']),
    actorSeatIdx: _readInt(map['actor_seat_idx']),
    actorUserId: _readInt(map['actor_user_id']),
    type: (map['ty'] as String?) ?? 'event',
    data: _castMap(map['data']) ?? const <String, Object?>{},
  );
}

int? _readInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}

double? _readDouble(Object? raw) {
  if (raw is double) return raw;
  if (raw is int) return raw.toDouble();
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw);
  return null;
}

DateTime? _readDate(Object? raw) {
  if (raw is String) {
    return DateTime.tryParse(raw)?.toLocal();
  }
  return null;
}

Map<String, Object?>? _castMap(Object? raw) {
  if (raw is Map) {
    return raw.cast<String, Object?>();
  }
  return null;
}

List<int>? _castIntList(Object? raw) {
  if (raw is! List) return null;
  final out = <int>[];
  for (final value in raw) {
    final parsed = _readInt(value);
    if (parsed == null) return null;
    out.add(parsed);
  }
  return out;
}
