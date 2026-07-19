/// The ONLY file that imports google_mobile_ads (incl. the UMP consent
/// classes). Compiled for every dart.library.io target; non-mobile platforms
/// and the GOAT_ADS=off dart-define get [NoopAdsService] at runtime.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ads_service.dart';

AdsService createAdsService() {
  // Dev escape hatch: --dart-define=GOAT_ADS=off silences ads on device.
  const flag = String.fromEnvironment('GOAT_ADS', defaultValue: 'on');
  if (flag == 'off') return NoopAdsService();
  if (!(Platform.isAndroid || Platform.isIOS)) return NoopAdsService();
  return MobileAdsService();
}

/// Real AdMob service: UMP consent gate → SDK init → preloaded rewarded +
/// interstitial with load-failure backoff. Every SDK call is wrapped so an
/// ads failure can never break the game loop.
class MobileAdsService implements AdsService {
  static const _backoffSeconds = [5, 10, 30, 60];

  final InterstitialPolicy _policy = const InterstitialPolicy();

  bool _initStarted = false;
  bool _sdkReady = false;
  bool _removeAds = false;
  bool _privacyOptionsRequired = false;
  bool _disposed = false;

  RewardedAd? _rewarded;
  InterstitialAd? _interstitial;
  int _rewardedFailures = 0;
  int _interstitialFailures = 0;
  Timer? _rewardedRetry;
  Timer? _interstitialRetry;

  SharedPreferences? _prefs;
  int _gamesFinishedTotal = 0;
  int _gamesSinceInterstitial = 0;
  DateTime? _lastInterstitialAt;

  String get _interstitialUnitId =>
      Platform.isAndroid ? AdIds.interstitialAndroid : AdIds.interstitialIos;
  String get _rewardedUnitId =>
      Platform.isAndroid ? AdIds.rewardedAndroid : AdIds.rewardedIos;

  @override
  bool get supported => true;

  @override
  bool get available => _sdkReady;

  @override
  bool get rewardedReady => _rewarded != null;

  @override
  bool get privacyOptionsRequired => _privacyOptionsRequired;

  @override
  set removeAds(bool value) {
    if (_removeAds == value) return;
    _removeAds = value;
    if (value) {
      // Buyers never see interstitials — stop holding one in memory. The
      // rewarded ad stays loaded: doubling is an opt-in benefit.
      _interstitialRetry?.cancel();
      _interstitial?.dispose();
      _interstitial = null;
    } else if (_sdkReady) {
      _loadInterstitial();
    }
  }

  @override
  Future<void> init() async {
    if (_initStarted) return;
    _initStarted = true;
    try {
      _prefs = await SharedPreferences.getInstance();
      _gamesFinishedTotal = _prefs?.getInt(AdsPrefs.gamesFinishedTotal) ?? 0;
      _gamesSinceInterstitial =
          _prefs?.getInt(AdsPrefs.gamesSinceInterstitial) ?? 0;
      final lastMs = _prefs?.getInt(AdsPrefs.lastInterstitialAtMs);
      _lastInterstitialAt =
          lastMs == null ? null : DateTime.fromMillisecondsSinceEpoch(lastMs);

      // UMP flow: update consent info, show the GDPR/US-state form only when
      // required (first-run EEA), then init the SDK only if ads may be
      // requested. On refusal: available stays false, retry next app start.
      final params = ConsentRequestParameters(
        consentDebugSettings: kDebugMode
            // Debug: pretend we're in the EEA so the form is exercisable.
            ? ConsentDebugSettings(
                debugGeography: DebugGeography.debugGeographyEea,
              )
            : null,
      );
      final updated = Completer<bool>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        params,
        () => updated.complete(true),
        (error) {
          debugPrint('ads: consent update failed: ${error.message}');
          updated.complete(false);
        },
      );
      if (await updated.future) {
        await ConsentForm.loadAndShowConsentFormIfRequired((error) {
          if (error != null) {
            debugPrint('ads: consent form: ${error.message}');
          }
        });
      }
      _privacyOptionsRequired = await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
      // canRequestAds may already be true from a previous session even when
      // this update round failed — always ask.
      if (!await ConsentInformation.instance.canRequestAds()) return;
      if (_disposed) return;

      await MobileAds.instance.initialize();
      _sdkReady = true;
      _loadRewarded();
      if (!_removeAds) _loadInterstitial();
    } catch (e) {
      // Ads must never break the app (e.g. missing Play services).
      debugPrint('ads: init failed: $e');
    }
  }

  // ------------------------------------------------------------- preloading

  void _loadRewarded() {
    if (_disposed || !_sdkReady || _rewardedUnitId.isEmpty) return;
    RewardedAd.load(
      adUnitId: _rewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (_disposed) {
            ad.dispose();
            return;
          }
          _rewardedFailures = 0;
          _rewarded = ad;
        },
        onAdFailedToLoad: (error) {
          debugPrint('ads: rewarded load failed: ${error.message}');
          _scheduleRetry(isRewarded: true);
        },
      ),
    );
  }

  void _loadInterstitial() {
    if (_disposed || !_sdkReady || _removeAds || _interstitialUnitId.isEmpty) {
      return;
    }
    InterstitialAd.load(
      adUnitId: _interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          if (_disposed || _removeAds) {
            ad.dispose();
            return;
          }
          _interstitialFailures = 0;
          _interstitial = ad;
        },
        onAdFailedToLoad: (error) {
          debugPrint('ads: interstitial load failed: ${error.message}');
          _scheduleRetry(isRewarded: false);
        },
      ),
    );
  }

  /// 5 → 10 → 30 → 60 s (capped) backoff, reset on a successful load.
  void _scheduleRetry({required bool isRewarded}) {
    if (_disposed) return;
    final failures = isRewarded ? _rewardedFailures : _interstitialFailures;
    final delay = Duration(
      seconds: _backoffSeconds[min(failures, _backoffSeconds.length - 1)],
    );
    if (isRewarded) {
      _rewardedFailures++;
      _rewardedRetry?.cancel();
      _rewardedRetry = Timer(delay, _loadRewarded);
    } else {
      _interstitialFailures++;
      _interstitialRetry?.cancel();
      _interstitialRetry = Timer(delay, _loadInterstitial);
    }
  }

  // ---------------------------------------------------------------- showing

  @override
  void notifyGameFinished() {
    _gamesFinishedTotal++;
    _gamesSinceInterstitial++;
    _prefs?.setInt(AdsPrefs.gamesFinishedTotal, _gamesFinishedTotal);
    _prefs?.setInt(AdsPrefs.gamesSinceInterstitial, _gamesSinceInterstitial);
  }

  @override
  Future<bool> maybeShowInterstitial(InterstitialTrigger trigger) async {
    final ad = _interstitial;
    final should = _policy.shouldShow(
      available: available,
      removeAds: _removeAds,
      gamesFinishedTotal: _gamesFinishedTotal,
      gamesSinceInterstitial: _gamesSinceInterstitial,
      lastShownAt: _lastInterstitialAt,
      now: clock.now(),
      loaded: ad != null,
    );
    if (!should || ad == null) return false;
    _interstitial = null;
    _gamesSinceInterstitial = 0;
    _lastInterstitialAt = clock.now();
    _prefs?.setInt(AdsPrefs.gamesSinceInterstitial, 0);
    _prefs?.setInt(
      AdsPrefs.lastInterstitialAtMs,
      _lastInterstitialAt!.millisecondsSinceEpoch,
    );
    final done = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitial();
        if (!done.isCompleted) done.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('ads: interstitial show failed: ${error.message}');
        ad.dispose();
        _loadInterstitial();
        if (!done.isCompleted) done.complete(false);
      },
    );
    try {
      await ad.show();
    } catch (e) {
      debugPrint('ads: interstitial show threw: $e');
      if (!done.isCompleted) done.complete(false);
    }
    return done.future;
  }

  @override
  Future<RewardedOutcome> showRewarded() async {
    final ad = _rewarded;
    if (ad == null) return RewardedOutcome.unavailable;
    _rewarded = null;
    var earned = false;
    final done = Completer<RewardedOutcome>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewarded();
        if (!done.isCompleted) {
          done.complete(
            earned ? RewardedOutcome.earned : RewardedOutcome.dismissed,
          );
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('ads: rewarded show failed: ${error.message}');
        ad.dispose();
        _loadRewarded();
        if (!done.isCompleted) done.complete(RewardedOutcome.failed);
      },
    );
    try {
      await ad.show(onUserEarnedReward: (_, _) => earned = true);
    } catch (e) {
      debugPrint('ads: rewarded show threw: $e');
      if (!done.isCompleted) done.complete(RewardedOutcome.failed);
    }
    return done.future;
  }

  @override
  Future<void> showPrivacyOptionsForm() async {
    try {
      await ConsentForm.showPrivacyOptionsForm((error) {
        if (error != null) {
          debugPrint('ads: privacy form: ${error.message}');
        }
      });
    } catch (e) {
      debugPrint('ads: privacy form threw: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _rewardedRetry?.cancel();
    _interstitialRetry?.cancel();
    _rewarded?.dispose();
    _rewarded = null;
    _interstitial?.dispose();
    _interstitial = null;
  }
}
