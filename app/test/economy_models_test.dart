/// Wire-tolerance tests for the economy models: an OLD server payload
/// (stats + achievements only) must parse with every economy field at its
/// default, the new payload must round-trip, GameRewards.fromWire must
/// survive partial maps, and the rank ladder must respect its bounds.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:goat_app/core/game/models.dart';
import 'package:goat_app/core/net/api.dart';
import 'package:goat_app/features/economy/ranks.dart';

void main() {
  group('PlayerProfile.fromJson', () {
    test('OLD payload (pre-economy server) parses with dormant defaults', () {
      final profile = PlayerProfile.fromJson({
        'stats': {'gamesPlayed': 12, 'gamesWon': 5, 'goats': 3, 'winStreak': 2},
        'achievements': [
          {'id': 'first_win', 'unlockedAt': 123},
        ],
      });
      expect(profile.stats.gamesPlayed, 12);
      expect(profile.unlocked, {'first_win'});
      expect(profile.coins, 0);
      expect(profile.rating, 1000);
      expect(profile.rankId, isNull);
      expect(profile.dailyStreak, 0);
      expect(profile.dailyClaimable, isFalse);
      expect(profile.weeklyCoins, 0);
      expect(profile.quests, isEmpty);
      expect(profile.ownedCosmetics, isEmpty);
      expect(profile.equipped.cardBack, 'back_classic');
      expect(profile.equipped.felt, 'felt_classic');
      expect(profile.removeAds, isFalse);
    });

    test('empty / garbage payload collapses to defaults', () {
      final profile = PlayerProfile.fromJson({
        'stats': 'nonsense',
        'coins': 'many',
        'quests': {'not': 'a list'},
        'equipped': 7,
      });
      expect(profile.coins, 0);
      expect(profile.rating, 1000);
      expect(profile.quests, isEmpty);
      expect(profile.equipped.cardBack, 'back_classic');
    });

    test('NEW payload parses every economy field', () {
      final profile = PlayerProfile.fromJson({
        'stats': {'gamesPlayed': 30, 'gamesWon': 15, 'goats': 4, 'winStreak': 3},
        'achievements': const [],
        'coins': 420,
        'rating': 1275,
        'rank': {'id': 'trump', 'ru': 'Козырный козёл', 'emoji': '🃏'},
        'dailyStreak': 4,
        'dailyClaimable': true,
        'weeklyCoins': 160,
        'quests': [
          {'id': 'play_3', 'ru': 'Сыграйте 3 партии', 'progress': 2, 'target': 3, 'reward': 15},
          {'id': 'win_1', 'ru': 'Выиграйте партию', 'progress': 1, 'target': 1, 'reward': 20, 'claimed': true},
        ],
        'ownedCosmetics': ['back_cabbage', 'felt_burgundy'],
        'equipped': {'cardBack': 'back_cabbage', 'felt': 'felt_burgundy'},
        'removeAds': true,
      });
      expect(profile.coins, 420);
      expect(profile.rating, 1275);
      expect(profile.rankId, 'trump');
      expect(profile.dailyStreak, 4);
      expect(profile.dailyClaimable, isTrue);
      expect(profile.weeklyCoins, 160);
      expect(profile.quests, hasLength(2));
      expect(profile.quests.first.id, 'play_3');
      expect(profile.quests.first.completed, isFalse);
      expect(profile.quests.last.completed, isTrue);
      expect(profile.ownedCosmetics, {'back_cabbage', 'felt_burgundy'});
      expect(profile.equipped.cardBack, 'back_cabbage');
      expect(profile.equipped.felt, 'felt_burgundy');
      expect(profile.removeAds, isTrue);
    });

    test('copyWith keeps untouched fields and can null rankId via sentinel', () {
      const profile = PlayerProfile(coins: 100, rating: 1200, rankId: 'scapegoat');
      final bumped = profile.copyWith(coins: 150);
      expect(bumped.coins, 150);
      expect(bumped.rating, 1200);
      expect(bumped.rankId, 'scapegoat');
      expect(profile.copyWith(rankId: null).rankId, isNull);
    });
  });

  group('GameRewards.fromWire', () {
    test('full payload', () {
      final rewards = GameRewards.fromWire({
        'type': 'gameRewards',
        'seq': 9,
        'coins': {'base': 20, 'margin': 5, 'flagBonus': 0, 'streakBonus': 5, 'questBonus': 15, 'total': 45},
        'breakdown': [
          {'ru': 'Победа', 'amount': 20},
          {'ru': 'Задание дня', 'amount': 15},
        ],
        'ratingDelta': 18,
        'rating': 1118,
        'rank': {'id': 'scapegoat', 'ru': 'Козёл отпущения', 'emoji': '🙃'},
        'questProgress': [
          {'id': 'win_1', 'ru': 'Выиграйте партию', 'progress': 1, 'target': 1, 'completed': true},
        ],
        'canDouble': true,
      });
      expect(rewards.coins, 45);
      expect(rewards.breakdown, hasLength(2));
      expect(rewards.breakdown.first.ru, 'Победа');
      expect(rewards.ratingDelta, 18);
      expect(rewards.rating, 1118);
      expect(rewards.rankId, 'scapegoat');
      expect(rewards.questProgress.single.completed, isTrue);
      expect(rewards.canDouble, isTrue);
      expect(rewards.anonymous, isFalse);
    });

    test('partial / anonymous payloads never throw', () {
      final anonymous = GameRewards.fromWire({'type': 'gameRewards', 'anonymous': true});
      expect(anonymous.anonymous, isTrue);
      expect(anonymous.coins, 0);
      expect(anonymous.breakdown, isEmpty);
      expect(anonymous.questProgress, isEmpty);

      final flat = GameRewards.fromWire({'coins': 30, 'ratingDelta': -8, 'rating': 992});
      expect(flat.coins, 30, reason: 'a flat coins number is accepted too');
      expect(flat.ratingDelta, -8);
      expect(flat.rankId, isNull);
    });
  });

  group('rankForRating', () {
    test('band bounds match the canonical ladder', () {
      expect(rankForRating(0).ru, 'Козлёнок');
      expect(rankForRating(-50).ru, 'Козлёнок', reason: 'clamps below zero');
      expect(rankForRating(899).ru, 'Козлёнок');
      expect(rankForRating(900).ru, 'Молодой козлик');
      expect(rankForRating(999).ru, 'Молодой козлик');
      expect(rankForRating(1000).ru, 'Козёл обыкновенный');
      expect(rankForRating(1099).ru, 'Козёл обыкновенный');
      expect(rankForRating(1100).ru, 'Козёл отпущения');
      expect(rankForRating(1250).ru, 'Козырный козёл');
      expect(rankForRating(1400).ru, 'Козёл-аристократ');
      expect(rankForRating(1550).ru, 'Козёл-профессор');
      expect(rankForRating(1749).ru, 'Козёл-профессор');
      expect(rankForRating(1750).ru, 'Матёрый козёл');
      expect(rankForRating(9000).ru, 'Матёрый козёл');
    });

    test('ladder is ascending and 8 ranks long', () {
      expect(rankDefs, hasLength(8));
      for (var i = 1; i < rankDefs.length; i++) {
        expect(rankDefs[i].minRating, greaterThan(rankDefs[i - 1].minRating));
      }
    });
  });
}
