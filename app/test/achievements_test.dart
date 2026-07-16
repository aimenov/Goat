import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:goat_app/core/net/api.dart';
import 'package:goat_app/features/achievements/achievements.dart';
import 'package:goat_app/features/achievements/achievements_screen.dart';

void main() {
  group('PlayerProfile.fromJson', () {
    test('parses stats and unlocked ids from the server payload', () {
      final profile = PlayerProfile.fromJson({
        'stats': {'gamesPlayed': 12, 'gamesWon': 5, 'goats': 3, 'winStreak': 2},
        'achievements': [
          {'id': 'first_win', 'en': 'Not the Goat Today', 'ru': 'Сегодня не козёл'},
          {'id': 'streak_5', 'en': 'Hot Hooves', 'ru': 'Горячие копыта'},
        ],
      });
      expect(profile.stats.gamesPlayed, 12);
      expect(profile.stats.gamesWon, 5);
      expect(profile.stats.goats, 3);
      expect(profile.stats.winStreak, 2);
      expect(profile.unlocked, {'first_win', 'streak_5'});
    });

    test('empty payload collapses to zero stats (fresh player)', () {
      final profile = PlayerProfile.fromJson({});
      expect(profile.stats.gamesPlayed, 0);
      expect(profile.stats.gamesWon, 0);
      expect(profile.stats.goats, 0);
      expect(profile.stats.winStreak, 0);
      expect(profile.unlocked, isEmpty);
    });
  });

  group('AchievementsBody', () {
    testWidgets('renders stats header plus locked and unlocked tiles',
        (tester) async {
      // Tall surface so the whole non-scrolling grid is laid out.
      tester.view.physicalSize = const Size(900, 2800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const profile = PlayerProfile(
        stats: ProfileStats(gamesPlayed: 12, gamesWon: 5, goats: 3, winStreak: 2),
        unlocked: {'first_win', 'streak_5'},
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AchievementsBody(profile: profile)),
        ),
      );
      await tester.pumpAndSettle(); // tile entrance stagger completes

      // Stats header values.
      expect(find.text('12'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('Раз козлом'), findsOneWidget);

      // All 12 tiles rendered with their titles and descriptions.
      for (final def in achievementDefs) {
        expect(find.text(def.title), findsOneWidget);
        expect(find.text(def.description), findsOneWidget);
      }

      // 10 locked tiles carry a lock icon; 2 unlocked do not.
      expect(find.byIcon(Icons.lock), findsNWidgets(10));
      expect(find.text('Открыто 2 из 12'), findsOneWidget);

      // Unlocked tiles show their emoji at full strength; locked tiles dim
      // theirs. (Each tile's entrance SlideFadeIn also uses an Opacity, but
      // it settles at 1.0 — only the locked-state wrapper stays dimmed.)
      bool dimmed(Finder emoji) => tester
          .widgetList<Opacity>(
            find.ancestor(of: emoji, matching: find.byType(Opacity)),
          )
          .any((o) => o.opacity < 1.0);
      final unlockedEmoji = find.text('🎉');
      expect(unlockedEmoji, findsOneWidget);
      expect(dimmed(unlockedEmoji), isFalse);
      expect(dimmed(find.text('👑')), isTrue);
    });

    testWidgets('fresh player: everything locked, zero stats', (tester) async {
      tester.view.physicalSize = const Size(900, 2800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AchievementsBody(profile: PlayerProfile())),
        ),
      );

      expect(find.byIcon(Icons.lock), findsNWidgets(12));
      expect(find.text('Открыто 0 из 12'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(4));
    });
  });
}
