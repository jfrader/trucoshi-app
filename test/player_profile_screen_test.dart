import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trucoshi_app/screens/player_profile_screen.dart';
import 'package:trucoshi_app/services/auth_service.dart';
import 'package:trucoshi_app/services/stats_repository.dart';

import 'helpers/fake_stats_repository.dart';

void main() {
  testWidgets('Player profile screen shows totals and loads more matches', (
    tester,
  ) async {
    final auth = AuthService();
    addTearDown(auth.dispose);
    auth.useToken('token', displayName: 'Fran');

    final repo = FakeStatsRepository();

    repo.playerProfileResponses.addAll([
      PlayerProfile(
        user: const PlayerProfileUser(id: 7, name: 'Fran'),
        totals: const PlayerProfileTotals(
          matchesPlayed: 30,
          matchesFinished: 28,
          matchesWon: 20,
          winRate: 0.71,
          pointsFor: 900,
          pointsAgainst: 700,
          pointsDiff: 200,
          lastPlayedAt: null,
        ),
        recentMatches: [
          PlayerMatchSummary(
            matchId: 111,
            wsMatchId: 'match-111',
            createdAt: DateTime.utc(2026, 3, 7, 12, 0),
            finishedAt: DateTime.utc(2026, 3, 7, 12, 30),
            seatIdx: 0,
            teamIdx: 0,
            matchOptions: const {'max_players': 4},
            teamPoints: const [30, 20],
            pointsFor: 30,
            pointsAgainst: 20,
            finishReason: 'completed',
            outcome: PlayerMatchOutcome.win,
          ),
        ],
        nextOffset: 10,
      ),
      PlayerProfile(
        user: const PlayerProfileUser(id: 7, name: 'Fran'),
        totals: const PlayerProfileTotals.empty(),
        recentMatches: [
          PlayerMatchSummary(
            matchId: 222,
            wsMatchId: 'match-222',
            createdAt: DateTime.utc(2026, 3, 6, 9, 0),
            finishedAt: DateTime.utc(2026, 3, 6, 9, 25),
            seatIdx: 1,
            teamIdx: 1,
            matchOptions: const {'max_players': 4},
            teamPoints: const [12, 30],
            pointsFor: 12,
            pointsAgainst: 30,
            finishReason: 'completed',
            outcome: PlayerMatchOutcome.loss,
          ),
        ],
        nextOffset: null,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerProfileScreen(auth: auth, userId: 7, stats: repo),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Fran'), findsWidgets);
    expect(find.textContaining('Match match-111'), findsOneWidget);
    expect(repo.playerProfileCalls.length, 1);
    expect(repo.playerProfileCalls.first.offset, isNull);

    expect(find.text('Load more matches'), findsOneWidget);
    await tester.tap(find.text('Load more matches'));
    await tester.pumpAndSettle();

    expect(repo.playerProfileCalls.length, 2);
    expect(repo.playerProfileCalls[1].offset, 10);
    expect(find.textContaining('match-222'), findsOneWidget);
  });
}
