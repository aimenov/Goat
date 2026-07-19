/// InterstitialPolicy decision table: pure unit tests over every capping
/// condition — availability, remove-ads, new-user grace, the once-per-2-games
/// cap, the 90 s guard and the preload requirement.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:goat_app/core/services/ads/ads_service.dart';

void main() {
  const policy = InterstitialPolicy();
  final now = DateTime.utc(2026, 7, 19, 12);

  /// Baseline where every condition holds — each test flips exactly one.
  bool decide({
    bool available = true,
    bool removeAds = false,
    int gamesFinishedTotal = 3,
    int gamesSinceInterstitial = 2,
    DateTime? lastShownAt,
    bool loaded = true,
  }) =>
      policy.shouldShow(
        available: available,
        removeAds: removeAds,
        gamesFinishedTotal: gamesFinishedTotal,
        gamesSinceInterstitial: gamesSinceInterstitial,
        lastShownAt: lastShownAt,
        now: now,
        loaded: loaded,
      );

  test('shows when every condition holds', () {
    expect(decide(), isTrue);
  });

  test('never on web/desktop/consent-refused (available=false)', () {
    expect(decide(available: false), isFalse);
  });

  test('never for remove-ads buyers', () {
    expect(decide(removeAds: true), isFalse);
  });

  test('never when no interstitial is preloaded', () {
    expect(decide(loaded: false), isFalse);
  });

  group('new-user grace (gamesFinishedTotal >= 3)', () {
    test('0, 1, 2 finished games — never', () {
      for (var games = 0; games < 3; games++) {
        expect(
          decide(gamesFinishedTotal: games, gamesSinceInterstitial: games),
          isFalse,
          reason: 'game #$games is inside the grace period',
        );
      }
    });

    test('3rd finished game is the first eligible exit', () {
      expect(decide(gamesFinishedTotal: 3, gamesSinceInterstitial: 3), isTrue);
    });
  });

  group('once per 2 finished games (gamesSinceInterstitial >= 2)', () {
    test('0 and 1 games since the last one — never', () {
      expect(decide(gamesSinceInterstitial: 0), isFalse);
      expect(decide(gamesSinceInterstitial: 1), isFalse);
    });

    test('2 games since the last one — eligible again', () {
      expect(decide(gamesSinceInterstitial: 2), isTrue);
    });
  });

  group('90 s minimum interval', () {
    test('89 s after the last show — never (short-game guard)', () {
      expect(
        decide(lastShownAt: now.subtract(const Duration(seconds: 89))),
        isFalse,
      );
    });

    test('exactly 90 s — eligible', () {
      expect(
        decide(lastShownAt: now.subtract(const Duration(seconds: 90))),
        isTrue,
      );
    });

    test('no interstitial ever shown — the guard does not apply', () {
      expect(decide(lastShownAt: null), isTrue);
    });
  });

  test('all blockers at once still refuse', () {
    expect(
      decide(
        available: false,
        removeAds: true,
        gamesFinishedTotal: 0,
        gamesSinceInterstitial: 0,
        lastShownAt: now,
        loaded: false,
      ),
      isFalse,
    );
  });
}
