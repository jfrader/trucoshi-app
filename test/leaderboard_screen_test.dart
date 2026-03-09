import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trucoshi_app/screens/leaderboard_screen.dart';
import 'package:trucoshi_app/services/auth_service.dart';
import 'package:trucoshi_app/services/stats_repository.dart';

import 'helpers/fake_stats_repository.dart';

void main() {
  testWidgets('Leaderboard screen renders entries, loads more, and filters', (
    tester,
  ) async {
    final auth = AuthService();
    addTearDown(auth.dispose);
    auth.continueAsGuest(displayName: 'Guest');

    final repo = FakeStatsRepository();

    repo.leaderboardResponses.addAll([
      LeaderboardPage(
        entries: [
          LeaderboardEntry(
            rank: 1,
            userId: 101,
            name: 'Fran',
            matchesPlayed: 20,
            matchesFinished: 18,
            matchesWon: 12,
            winRate: 0.66,
            pointsFor: 450,
            pointsAgainst: 320,
            pointsDiff: 130,
            lastPlayedAt: DateTime.utc(2026, 3, 8),
          ),
        ],
        nextOffset: 25,
      ),
      LeaderboardPage(
        entries: [
          LeaderboardEntry(
            rank: 2,
            userId: 202,
            name: 'Lia',
            matchesPlayed: 15,
            matchesFinished: 14,
            matchesWon: 9,
            winRate: 0.64,
            pointsFor: 300,
            pointsAgainst: 200,
            pointsDiff: 100,
            lastPlayedAt: DateTime.utc(2026, 3, 7),
          ),
        ],
        nextOffset: null,
      ),
      LeaderboardPage(
        entries: [
          LeaderboardEntry(
            rank: 1,
            userId: 303,
            name: 'Mia',
            matchesPlayed: 30,
            matchesFinished: 30,
            matchesWon: 25,
            winRate: 0.83,
            pointsFor: 900,
            pointsAgainst: 400,
            pointsDiff: 500,
            lastPlayedAt: DateTime.utc(2026, 3, 6),
          ),
        ],
        nextOffset: null,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: LeaderboardScreen(auth: auth, stats: repo),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Fran'), findsOneWidget);
    expect(repo.leaderboardCalls, isNotEmpty);
    expect(repo.leaderboardCalls.first.minFinished, 5);

    expect(find.text('Load more'), findsOneWidget);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();

    expect(repo.leaderboardCalls.length, 2);
    expect(repo.leaderboardCalls[1].offset, 25);
    expect(find.text('Lia'), findsOneWidget);

    await tester.tap(find.text('10+'));
    await tester.pumpAndSettle();

    expect(repo.leaderboardCalls.length, 3);
    expect(repo.leaderboardCalls.last.minFinished, 10);
    expect(find.text('Mia'), findsOneWidget);
  });
}
