/// Pure-widget tests for the lobby [ProfileHeader]: rank derivation from
/// rating, chip contents and tap callbacks.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:goat_app/core/net/api.dart';
import 'package:goat_app/features/lobby/profile_header.dart';

Future<void> pumpHeader(
  WidgetTester tester, {
  required PlayerProfile profile,
  VoidCallback? onCoins,
  VoidCallback? onRating,
  VoidCallback? onQuests,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ProfileHeader(
          nickname: 'Ася',
          profile: profile,
          onCoins: onCoins,
          onRating: onRating,
          onQuests: onQuests,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows nickname, derived rank, coins, streak and quest count',
      (tester) async {
    await pumpHeader(
      tester,
      profile: const PlayerProfile(
        coins: 230,
        rating: 1275,
        dailyStreak: 3,
        quests: [
          QuestState(id: 'a', ru: 'x', progress: 3, target: 3, reward: 15),
          QuestState(id: 'b', ru: 'y', progress: 1, target: 5, reward: 15),
          QuestState(id: 'c', ru: 'z', progress: 0, target: 2, reward: 20),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('Ася'), findsOneWidget);
    // 1275 sits in the «Козырный козёл» band (1250..1399).
    expect(find.text('Козырный козёл'), findsOneWidget);
    expect(find.text('🃏'), findsOneWidget);
    expect(find.text('⭐ 1275'), findsOneWidget);
    expect(find.text('🥬 230'), findsOneWidget);
    expect(find.text('🔥 3'), findsOneWidget);
    expect(find.text('Задания 1/3'), findsOneWidget);
  });

  testWidgets('empty profile: default rank, zero chips, quests 0/3',
      (tester) async {
    await pumpHeader(tester, profile: const PlayerProfile());
    await tester.pump();

    expect(find.text('Козёл обыкновенный'), findsOneWidget);
    expect(find.text('⭐ 1000'), findsOneWidget);
    expect(find.text('🥬 0'), findsOneWidget);
    expect(find.text('🔥 0'), findsOneWidget);
    expect(find.text('Задания 0/3'), findsOneWidget);
  });

  testWidgets('chips fire their tap callbacks', (tester) async {
    var coins = 0;
    var rating = 0;
    var quests = 0;
    await pumpHeader(
      tester,
      profile: const PlayerProfile(coins: 50, rating: 1000),
      onCoins: () => coins++,
      onRating: () => rating++,
      onQuests: () => quests++,
    );
    await tester.pump();

    await tester.tap(find.text('🥬 50'));
    await tester.tap(find.text('⭐ 1000'));
    await tester.tap(find.text('Задания 0/3'));
    expect(coins, 1);
    expect(rating, 1);
    expect(quests, 1);
  });
}
