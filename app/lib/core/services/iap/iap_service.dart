/// IAP facade: the app talks to [IapService] only; in_app_purchase is
/// imported exclusively by `iap_service_mobile.dart`, selected via the
/// `dart.library.io` conditional import below, so web builds never compile
/// the plugin. Desktop VMs compile the mobile file but get [NoopIapService]
/// from the runtime Platform check inside it.
library;

import 'iap_service_stub.dart'
    if (dart.library.io) 'iap_service_mobile.dart' as impl;

/// Store product ids — the same strings in Play Console / App Store Connect
/// and in the server catalog (packages/shared economy.ts IAP_PRODUCTS).
abstract final class ProductIds {
  static const removeAds = 'goat.remove_ads'; // non-consumable
  static const coinsSmall = 'goat.coins.small'; // consumable
  static const coinsMedium = 'goat.coins.medium'; // consumable
  static const coinsLarge = 'goat.coins.large'; // consumable
  static const cardbackGolden = 'goat.cardback.golden'; // non-consumable
  static const tableCabbage = 'goat.table.cabbage'; // non-consumable

  static const Set<String> consumables = {coinsSmall, coinsMedium, coinsLarge};
  static const Set<String> all = {
    removeAds,
    coinsSmall,
    coinsMedium,
    coinsLarge,
    cardbackGolden,
    tableCabbage,
  };
}

enum IapEventType { granted, restoredGranted, pending, canceled, error }

/// One terminal (or pending) outcome on the purchase stream.
class IapEvent {
  final IapEventType type;
  final String productId;
  final String? message;
  const IapEvent(this.type, this.productId, {this.message});
}

/// Store-catalog entry with the localized price string.
class IapProduct {
  final String id;
  final String title;
  final String description;
  final String price; // localized, e.g. «199,00 ₽»
  final bool consumable;
  const IapProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.consumable,
  });
}

/// Server redemption seam, injected by MonetizationController so the service
/// stays store-only (no api/session imports). Must resolve true only when the
/// purchase is settled server-side (granted now or already redeemed) — only
/// then may the service acknowledge it with the store.
typedef RedeemFn = Future<bool> Function(
  String platform,
  String productId,
  String verificationToken,
);

abstract class IapService {
  /// Attaches the purchase-stream listener. Must run early (app start):
  /// Android redelivers unacknowledged purchases and iOS queued transactions
  /// as soon as someone listens.
  Future<void> init();

  /// Whether this implementation could ever reach a store (identifies the
  /// real mobile service) — static UI gating.
  bool get supported;

  /// Store reachable (isAvailable() snapshot taken at [init]).
  bool get available;

  /// Loads the catalog; unknown ids are logged and skipped.
  Future<List<IapProduct>> loadProducts();

  /// Starts the store purchase flow; outcomes arrive via [events].
  Future<void> buy(String productId);

  /// Replays owned non-consumables through the same redeem path. Must stay
  /// reachable from the shop UI (App Store guideline 3.1.1).
  Future<void> restorePurchases();

  Stream<IapEvent> get events;

  void dispose();
}

/// Web/desktop/tests: no store, empty catalog, silent event stream.
class NoopIapService implements IapService {
  @override
  Future<void> init() async {}

  @override
  bool get supported => false;

  @override
  bool get available => false;

  @override
  Future<List<IapProduct>> loadProducts() async => const [];

  @override
  Future<void> buy(String productId) async {}

  @override
  Future<void> restorePurchases() async {}

  @override
  Stream<IapEvent> get events => const Stream.empty();

  @override
  void dispose() {}
}

IapService createIapService(RedeemFn redeem) => impl.createIapService(redeem);
