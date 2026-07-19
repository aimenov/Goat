/// Ads facade: the app talks to [AdsService] only; google_mobile_ads is
/// imported exclusively by `ads_service_mobile.dart`, selected via the
/// `dart.library.io` conditional import below (render_mode.dart pattern), so
/// web builds never compile the plugin. Desktop VMs compile the mobile file
/// but get [NoopAdsService] from the runtime Platform check inside it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ads_service_stub.dart'
    if (dart.library.io) 'ads_service_mobile.dart' as impl;

/// How a rewarded-ad request ended for the caller.
enum RewardedOutcome { earned, dismissed, unavailable, failed }

/// Deliberately the only interstitial placement: leaving to the lobby from
/// the game-over overlay. Never mid-game, never before a rematch.
enum InterstitialTrigger { leaveToLobby }

abstract class AdsService {
  /// Idempotent and tolerant (sound.dart style): runs the UMP consent flow,
  /// then SDK init and preloading. Call from the lobby's first frame so the
  /// consent form never covers login or the game table.
  Future<void> init();

  /// Whether this implementation could ever serve ads (identifies the real
  /// mobile service before [init] resolves) — static UI gating.
  bool get supported;

  /// Mobile, GOAT_ADS!=off, consent obtained and SDK initialized.
  bool get available;

  /// UI: show the «Удвоить капусту» button only when a rewarded ad is loaded.
  bool get rewardedReady;

  /// UMP privacyOptionsRequirementStatus == required → settings must expose
  /// [showPrivacyOptionsForm] (GDPR consent withdrawal).
  bool get privacyOptionsRequired;

  /// Pushed by MonetizationController; true stops interstitial preloading.
  set removeAds(bool value);

  /// Call once per gameOver transition; bumps the capping counters.
  void notifyGameFinished();

  /// Shows the interstitial when the whole [InterstitialPolicy] holds; true
  /// if shown (resolves on dismiss). Never blocks when not ready.
  Future<bool> maybeShowInterstitial(InterstitialTrigger trigger);

  /// Shows the rewarded ad if loaded; resolves after dismiss.
  Future<RewardedOutcome> showRewarded();

  /// Settings-screen entry for consent withdrawal.
  Future<void> showPrivacyOptionsForm();

  void dispose();
}

/// Web/desktop/tests and the GOAT_ADS=off escape: every surface stays dormant.
class NoopAdsService implements AdsService {
  @override
  Future<void> init() async {}

  @override
  bool get supported => false;

  @override
  bool get available => false;

  @override
  bool get rewardedReady => false;

  @override
  bool get privacyOptionsRequired => false;

  @override
  set removeAds(bool value) {}

  @override
  void notifyGameFinished() {}

  @override
  Future<bool> maybeShowInterstitial(InterstitialTrigger trigger) async =>
      false;

  @override
  Future<RewardedOutcome> showRewarded() async => RewardedOutcome.unavailable;

  @override
  Future<void> showPrivacyOptionsForm() async {}

  @override
  void dispose() {}
}

/// SharedPreferences keys for the interstitial capping counters.
abstract final class AdsPrefs {
  static const gamesFinishedTotal = 'ads.gamesFinishedTotal';
  static const gamesSinceInterstitial = 'ads.gamesSinceInterstitial';
  static const lastInterstitialAtMs = 'ads.lastInterstitialAtMs';
}

/// Interstitial capping decision — pure, so the full table is unit-testable.
/// ALL conditions must hold; the trigger («leaveToLobby from game-over only»)
/// is enforced at the call site by [InterstitialTrigger] having one value.
class InterstitialPolicy {
  const InterstitialPolicy({
    this.minGamesBeforeFirst = 3,
    this.minGamesBetween = 2,
    this.minInterval = const Duration(seconds: 90),
  });

  /// New-user grace: no interstitials during the first games ever.
  final int minGamesBeforeFirst;

  /// «At most one per N finished games» cap.
  final int minGamesBetween;

  /// Guard against very short games / quick leave-rejoin loops.
  final Duration minInterval;

  bool shouldShow({
    required bool available,
    required bool removeAds,
    required int gamesFinishedTotal,
    required int gamesSinceInterstitial,
    required DateTime? lastShownAt,
    required DateTime now,
    required bool loaded,
  }) {
    if (!available || removeAds || !loaded) return false;
    if (gamesFinishedTotal < minGamesBeforeFirst) return false;
    if (gamesSinceInterstitial < minGamesBetween) return false;
    if (lastShownAt != null && now.difference(lastShownAt) < minInterval) {
      return false;
    }
    return true;
  }
}

/// Ad-unit ids. Real ids arrive via --dart-define (names below, documented in
/// docs/MONETIZATION.md); debug builds default to Google's canonical public
/// TEST units; release without defines gets '' → that format fails closed.
///
/// App ids (manifest/plist, not dart-defines):
///   Android test app id: ca-app-pub-3940256099942544~3347511713
///   iOS test app id:     ca-app-pub-3940256099942544~1458002511
abstract final class AdIds {
  static const _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const _testInterstitialIos = 'ca-app-pub-3940256099942544/4411468910';
  static const _testRewardedIos = 'ca-app-pub-3940256099942544/1712485313';

  static const interstitialAndroid = String.fromEnvironment(
    'GOAT_AD_INTERSTITIAL_ANDROID',
    defaultValue: kDebugMode ? _testInterstitialAndroid : '',
  );
  static const rewardedAndroid = String.fromEnvironment(
    'GOAT_AD_REWARDED_ANDROID',
    defaultValue: kDebugMode ? _testRewardedAndroid : '',
  );
  static const interstitialIos = String.fromEnvironment(
    'GOAT_AD_INTERSTITIAL_IOS',
    defaultValue: kDebugMode ? _testInterstitialIos : '',
  );
  static const rewardedIos = String.fromEnvironment(
    'GOAT_AD_REWARDED_IOS',
    defaultValue: kDebugMode ? _testRewardedIos : '',
  );
}

final adsServiceProvider = Provider<AdsService>((ref) {
  final service = impl.createAdsService();
  ref.onDispose(service.dispose);
  return service;
});
