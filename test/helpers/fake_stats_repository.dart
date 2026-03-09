import 'dart:collection';

import 'package:trucoshi_app/services/stats_repository.dart';

class FakeStatsRepository implements StatsRepository {
  final leaderboardResponses = ListQueue<LeaderboardPage>();
  final playerProfileResponses = ListQueue<PlayerProfile>();
  final matchHistoryResponses = ListQueue<MatchHistory>();

  final leaderboardCalls = <LeaderboardCall>[];
  final playerProfileCalls = <PlayerProfileCall>[];
  final matchHistoryCalls = <MatchHistoryCall>[];

  @override
  Future<LeaderboardPage> fetchLeaderboard({
    int limit = 25,
    int? offset,
    int minFinished = 5,
  }) async {
    leaderboardCalls.add(
      LeaderboardCall(limit: limit, offset: offset, minFinished: minFinished),
    );
    if (leaderboardResponses.isEmpty) {
      return const LeaderboardPage(entries: [], nextOffset: null);
    }
    return leaderboardResponses.removeFirst();
  }

  @override
  Future<PlayerProfile> fetchPlayerProfile(
    int userId, {
    int limit = 20,
    int? offset,
  }) async {
    playerProfileCalls.add(
      PlayerProfileCall(userId: userId, limit: limit, offset: offset),
    );
    if (playerProfileResponses.isEmpty) {
      return PlayerProfile(
        user: PlayerProfileUser(id: userId, name: 'unknown'),
        totals: const PlayerProfileTotals.empty(),
        recentMatches: const [],
      );
    }
    return playerProfileResponses.removeFirst();
  }

  @override
  Future<MatchHistory> fetchMatchHistory(
    String matchId, {
    int limit = 200,
    int? afterSeq,
  }) async {
    matchHistoryCalls.add(
      MatchHistoryCall(matchId: matchId, limit: limit, afterSeq: afterSeq),
    );
    if (matchHistoryResponses.isEmpty) {
      return MatchHistory(
        id: 0,
        wsMatchId: matchId,
        options: const {},
        players: const [],
        events: const [],
      );
    }
    return matchHistoryResponses.removeFirst();
  }

  @override
  void dispose() {}
}

class LeaderboardCall {
  LeaderboardCall({
    required this.limit,
    required this.offset,
    required this.minFinished,
  });

  final int limit;
  final int? offset;
  final int minFinished;
}

class PlayerProfileCall {
  PlayerProfileCall({
    required this.userId,
    required this.limit,
    required this.offset,
  });

  final int userId;
  final int limit;
  final int? offset;
}

class MatchHistoryCall {
  MatchHistoryCall({
    required this.matchId,
    required this.limit,
    required this.afterSeq,
  });

  final String matchId;
  final int limit;
  final int? afterSeq;
}
