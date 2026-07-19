/// Pure-widget tests for the leaderboard body: medal / numbered positions,
/// per-scope trailing stats, the own-row highlight and the off-list footer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:goat_app/core/net/api.dart';
import 'package:goat_app/features/leaderboard/leaderboard_screen.dart';

const _entries = [
  LeaderboardEntry(position: 1, playerId: 'p1', nickname: 'Ася', rating: 1810, weeklyCoins: 320),
  LeaderboardEntry(position: 2, playerId: 'p2', nickname: 'Борис', rating: 1420, weeklyCoins: 260),
  LeaderboardEntry(position: 3, playerId: 'p3', nickname: 'Вера', rating: 1275, weeklyCoins: 150),
  LeaderboardEntry(position: 4, playerId: 'p4', nickname: 'Глеб', rating: 1010, weeklyCoins: 40),
];

Future<void> pumpBoard(
  WidgetTester tester, {
  required LeaderboardData data,
  String scope = 'weekly',
  String? myPlayerId,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LeaderboardBody(
          data: data,
          scope: scope,
          myPlayerId: myPlayerId,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('medals for the top 3, numbers beyond, weekly 🥬 trailing',
      (tester) async {
    await pumpBoard(tester, data: const LeaderboardData(entries: _entries));

    expect(find.text('🥇'), findsOneWidget);
    expect(find.text('🥈'), findsOneWidget);
    expect(find.text('🥉'), findsOneWidget);
    expect(find.text('4.'), findsOneWidget);
    expect(find.text('🥬 320'), findsOneWidget);
    expect(find.text('🥬 40'), findsOneWidget);
  });

  testWidgets('alltime scope trails rank emoji + rating', (tester) async {
    await pumpBoard(
      tester,
      data: const LeaderboardData(entries: _entries),
      scope: 'alltime',
    );

    expect(find.text('🔥 1810'), findsOneWidget); // ≥1750 «Матёрый козёл»
    expect(find.text('🎩 1420'), findsOneWidget); // 1400 band
    expect(find.text('🃏 1275'), findsOneWidget); // 1250 band
    expect(find.text('🥬 320'), findsNothing);
  });

  testWidgets('own row is highlighted; no footer when listed', (tester) async {
    await pumpBoard(
      tester,
      data: const LeaderboardData(
        entries: _entries,
        me: LeaderboardEntry(position: 3, playerId: 'p3', nickname: 'Вера', rating: 1275, weeklyCoins: 150),
      ),
      myPlayerId: 'p3',
    );

    expect(find.byKey(const ValueKey('lb-own-row')), findsOneWidget);
    expect(find.byKey(const ValueKey('lb-me-footer')), findsNothing);
  });

  testWidgets('off-list me: sticky footer with the known position',
      (tester) async {
    await pumpBoard(
      tester,
      data: const LeaderboardData(
        entries: _entries,
        me: LeaderboardEntry(position: 12, playerId: 'me', nickname: 'Я', rating: 990, weeklyCoins: 15),
      ),
      myPlayerId: 'me',
    );

    expect(find.byKey(const ValueKey('lb-own-row')), findsNothing);
    expect(find.byKey(const ValueKey('lb-me-footer')), findsOneWidget);
    expect(find.text('Вы — 12-е место'), findsOneWidget);
    expect(find.text('🥬 15'), findsOneWidget);
  });

  testWidgets('off-list me without a position: own stats only',
      (tester) async {
    await pumpBoard(
      tester,
      data: const LeaderboardData(
        entries: _entries,
        me: LeaderboardEntry(playerId: 'me', nickname: 'Я', rating: 990, weeklyCoins: 15),
      ),
      myPlayerId: 'me',
    );

    expect(find.byKey(const ValueKey('lb-me-footer')), findsOneWidget);
    expect(find.text('Вы: Я'), findsOneWidget);
    expect(find.textContaining('-е место'), findsNothing);
  });

  testWidgets('empty board shows the placeholder', (tester) async {
    await pumpBoard(tester, data: const LeaderboardData());
    expect(find.text('Таблица пока пуста'), findsOneWidget);
  });
}
