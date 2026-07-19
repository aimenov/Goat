/// Monetization glue: bridges the ads/IAP service facades to the server API
/// and the profile, and provides the real implementations of the C1 hook
/// seams (core/monetization/hooks.dart) that main.dart installs as provider
/// overrides. All grants stay server-authoritative — this layer only relays
/// receipts and refreshes the profile.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Override (the provider-overrides list element type) lives in misc.dart in
// Riverpod 3.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

import 'monetization/hooks.dart';
import 'profile.dart';
import 'services/ads/ads_service.dart';
import 'services/iap/iap_service.dart';
import 'session.dart';

/// SharedPreferences cache of the remove-ads entitlement so interstitial
/// gating works offline before the first profile fetch lands.
const _removeAdsPref = 'iap.removeAds';

final iapServiceProvider = Provider<IapService>((ref) {
  // The redeem seam: called by the store service for every purchased or
  // restored transaction. False = not settled server-side → the service
  // leaves the purchase unacknowledged and the store retries next launch.
  Future<bool> redeem(
    String platform,
    String productId,
    String purchaseToken,
  ) async {
    final identity = ref.read(identityProvider).value;
    if (identity == null) return false; // signed out: retry after login
    try {
      final result = await ref.read(apiProvider).iapRedeem(
            identity.token,
            platform: platform,
            productId: productId,
            purchaseToken: purchaseToken,
          );
      return result != null; // null = endpoint absent (older server)
    } catch (_) {
      return false; // network/server error: keep the purchase pending
    }
  }

  final service = createIapService(redeem);
  ref.onDispose(service.dispose);
  return service;
});

class MonetizationState {
  /// Server profile ∨ prefs cache. v1 never revokes (refunds are handled by
  /// the v2 RTDN/App Store notification roadmap, see docs/MONETIZATION.md),
  /// so an offline empty profile can't strip a buyer of the entitlement.
  final bool removeAds;

  /// Store catalog, loaded lazily via [MonetizationController.loadProducts].
  final List<IapProduct> products;

  /// Product ids with a store flow currently in flight.
  final Set<String> pending;

  const MonetizationState({
    this.removeAds = false,
    this.products = const [],
    this.pending = const {},
  });

  MonetizationState copyWith({
    bool? removeAds,
    List<IapProduct>? products,
    Set<String>? pending,
  }) =>
      MonetizationState(
        removeAds: removeAds ?? this.removeAds,
        products: products ?? this.products,
        pending: pending ?? this.pending,
      );
}

class MonetizationController extends Notifier<MonetizationState> {
  @override
  MonetizationState build() {
    final iap = ref.watch(iapServiceProvider);
    final sub = iap.events.listen(_onIapEvent);
    ref.onDispose(sub.cancel);
    // Seed remove-ads from the prefs cache, then let the server profile
    // confirm it; both only ever upgrade false → true in v1.
    SharedPreferences.getInstance().then((prefs) {
      if (prefs.getBool(_removeAdsPref) ?? false) _adoptRemoveAds();
    });
    ref.listen(profileProvider, (_, next) {
      if (next.value?.removeAds ?? false) _adoptRemoveAds();
    });
    if (ref.read(profileProvider).value?.removeAds ?? false) {
      // Profile already loaded before this controller woke up.
      Future.microtask(_adoptRemoveAds);
    }
    return const MonetizationState();
  }

  void _adoptRemoveAds() {
    ref.read(adsServiceProvider).removeAds = true;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_removeAdsPref, true));
    if (!state.removeAds) state = state.copyWith(removeAds: true);
  }

  void _onIapEvent(IapEvent event) {
    switch (event.type) {
      case IapEventType.pending:
        state = state.copyWith(pending: {...state.pending, event.productId});
      case IapEventType.granted || IapEventType.restoredGranted:
        if (event.productId == ProductIds.removeAds) _adoptRemoveAds();
        // Coins/cosmetics come back authoritative with the fresh profile.
        unawaited(ref.read(profileProvider.notifier).refresh());
        state = state.copyWith(
          pending: {...state.pending}..remove(event.productId),
        );
      case IapEventType.canceled || IapEventType.error:
        state = state.copyWith(
          pending: {...state.pending}..remove(event.productId),
        );
    }
  }

  /// Loads the store catalog into [MonetizationState.products].
  Future<void> loadProducts() async {
    final iap = ref.read(iapServiceProvider);
    if (!iap.supported) return;
    await iap.init();
    final products = await iap.loadProducts();
    if (products.isNotEmpty) state = state.copyWith(products: products);
  }

  /// Runs the store purchase flow for [productId]; resolves once the first
  /// terminal outcome for that product arrives (redemption included). The
  /// timeout only unblocks the caller's UI — a purchase that completes later
  /// is still granted through the stream handler above.
  Future<bool> purchase(String productId) async {
    final iap = ref.read(iapServiceProvider);
    if (!iap.supported) return false;
    await iap.init();
    state = state.copyWith(pending: {...state.pending, productId});
    try {
      // Subscribe before buy(): a fast outcome must not slip past us.
      final terminal = iap.events.firstWhere(
        (e) => e.productId == productId && e.type != IapEventType.pending,
      );
      await iap.buy(productId);
      final event = await terminal.timeout(const Duration(minutes: 5));
      return event.type == IapEventType.granted ||
          event.type == IapEventType.restoredGranted;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    } finally {
      state = state.copyWith(pending: {...state.pending}..remove(productId));
    }
  }

  /// «Восстановить покупки»: replays owned non-consumables through the same
  /// redeem path (idempotent server-side), then re-fetches the profile.
  Future<void> restore() async {
    final iap = ref.read(iapServiceProvider);
    if (!iap.supported) return;
    await iap.init();
    await iap.restorePurchases();
    await ref.read(profileProvider.notifier).refresh();
  }
}

final monetizationProvider =
    NotifierProvider<MonetizationController, MonetizationState>(
        MonetizationController.new);

// ---------------------------------------------------------------------------
// C1 hook implementations. main.dart installs these as overrides of the null
// defaults in core/monetization/hooks.dart, so every C1/C2 surface (rewards
// block, daily sheet, shop) lights up without changing a line of UI code.

class _AdsRewardedHook implements RewardedAdHook {
  _AdsRewardedHook(this._ads);
  final AdsService _ads;

  @override
  Future<bool> show(String kind) async =>
      // [kind] picks the server wire ('doubleGame'/'doubleDaily') in the
      // caller's follow-up /ads/reward call; the ad itself is the same unit.
      await _ads.showRewarded() == RewardedOutcome.earned;
}

class _MonetizationIapHook implements IapHook {
  _MonetizationIapHook(this._ref);
  final Ref _ref;

  @override
  Future<bool> purchase(String productId) =>
      _ref.read(monetizationProvider.notifier).purchase(productId);
}

/// Provider overrides for runApp: hooks stay null (surfaces hidden) on
/// platforms whose service is a stub — web, desktop, GOAT_ADS=off.
final monetizationOverrides = <Override>[
  rewardedAdHookProvider.overrideWith((ref) {
    final ads = ref.watch(adsServiceProvider);
    return ads.supported ? _AdsRewardedHook(ads) : null;
  }),
  iapHookProvider.overrideWith((ref) {
    final iap = ref.watch(iapServiceProvider);
    return iap.supported ? _MonetizationIapHook(ref) : null;
  }),
];
