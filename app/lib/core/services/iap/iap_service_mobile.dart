/// The ONLY file that imports in_app_purchase (and its Android platform
/// addition). Compiled for every dart.library.io target; non-mobile platforms
/// get [NoopIapService] at runtime.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'iap_service.dart';

IapService createIapService(RedeemFn redeem) {
  if (!(Platform.isAndroid || Platform.isIOS)) return NoopIapService();
  return MobileIapService(redeem);
}

/// Real store service. The purchase stream is the single sink for every
/// outcome — user-initiated buys, startup redeliveries and restores all land
/// in [_handle], which redeems server-side BEFORE acknowledging with the
/// store: an unacknowledged purchase is redelivered on the next launch (and
/// auto-refunded by Play after ~3 days if we never manage to redeem it),
/// which is exactly the retry semantics we want for real money.
class MobileIapService implements IapService {
  MobileIapService(this._redeem);

  final RedeemFn _redeem;
  final StreamController<IapEvent> _events = StreamController.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool _initStarted = false;
  bool _available = false;

  /// Purchases are processed strictly one at a time: a batch redelivery must
  /// not fire concurrent /iap/redeem calls.
  Future<void> _chain = Future.value();

  /// Catalog cache for [buy] (PurchaseParam needs the ProductDetails).
  final Map<String, ProductDetails> _details = {};

  @override
  bool get supported => true;

  @override
  bool get available => _available;

  @override
  Stream<IapEvent> get events => _events.stream;

  @override
  Future<void> init() async {
    if (_initStarted) return;
    _initStarted = true;
    try {
      // Listen BEFORE anything else: attaching the listener is what makes
      // Android redeliver unacknowledged purchases and iOS flush queued
      // transactions.
      _sub = InAppPurchase.instance.purchaseStream.listen(
        _onPurchases,
        onError: (Object e) => debugPrint('iap: stream error: $e'),
      );
      _available = await InAppPurchase.instance.isAvailable();
    } catch (e) {
      // A broken store must never break the app.
      debugPrint('iap: init failed: $e');
    }
  }

  @override
  Future<List<IapProduct>> loadProducts() async {
    if (!_available) return const [];
    try {
      final response =
          await InAppPurchase.instance.queryProductDetails(ProductIds.all);
      if (response.notFoundIDs.isNotEmpty) {
        // Expected until the products exist in the console AND the app is on
        // a testing track (see docs/MONETIZATION.md).
        debugPrint('iap: not in catalog: ${response.notFoundIDs}');
      }
      for (final d in response.productDetails) {
        _details[d.id] = d;
      }
      return [
        for (final d in response.productDetails)
          IapProduct(
            id: d.id,
            title: d.title,
            description: d.description,
            price: d.price,
            consumable: ProductIds.consumables.contains(d.id),
          ),
      ];
    } catch (e) {
      debugPrint('iap: loadProducts failed: $e');
      return const [];
    }
  }

  @override
  Future<void> buy(String productId) async {
    var details = _details[productId];
    if (details == null) {
      await loadProducts();
      details = _details[productId];
    }
    if (details == null) {
      _events.add(IapEvent(
        IapEventType.error,
        productId,
        message: 'товар недоступен',
      ));
      return;
    }
    final param = PurchaseParam(productDetails: details);
    // autoConsume:false — the coin pack is consumed manually in [_handle]
    // only after the server confirmed the grant.
    if (ProductIds.consumables.contains(productId)) {
      await InAppPurchase.instance
          .buyConsumable(purchaseParam: param, autoConsume: false);
    } else {
      await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
    }
  }

  @override
  Future<void> restorePurchases() async {
    if (!_available) return;
    // Restored non-consumables re-arrive on the purchase stream; the redeem
    // endpoint dedupes by token, so replaying them is idempotent.
    await InAppPurchase.instance.restorePurchases();
  }

  void _onPurchases(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      _chain = _chain.then((_) => _handle(purchase));
    }
  }

  Future<void> _handle(PurchaseDetails purchase) async {
    switch (purchase.status) {
      case PurchaseStatus.pending:
        _events.add(IapEvent(IapEventType.pending, purchase.productID));
      case PurchaseStatus.canceled:
        // iOS delivers canceled transactions that still need finishing.
        await _completeQuietly(purchase);
        _events.add(IapEvent(IapEventType.canceled, purchase.productID));
      case PurchaseStatus.error:
        await _completeQuietly(purchase);
        _events.add(IapEvent(
          IapEventType.error,
          purchase.productID,
          message: purchase.error?.message,
        ));
      case PurchaseStatus.purchased || PurchaseStatus.restored:
        await _redeemAndFinish(purchase);
    }
  }

  /// The real-money path. Order matters:
  /// 1. server redeem (grant + dedupe) — on failure we stop WITHOUT touching
  ///    the store, so the purchase stays unacknowledged and is redelivered;
  /// 2. Android consumables: manual consumePurchase (autoConsume:false means
  ///    completePurchase alone would only acknowledge — the pack could never
  ///    be repurchased);
  /// 3. completePurchase (acknowledge / finishTransaction).
  Future<void> _redeemAndFinish(PurchaseDetails purchase) async {
    var settled = false;
    try {
      settled = await _redeem(
        Platform.isAndroid ? 'android' : 'ios',
        purchase.productID,
        purchase.verificationData.serverVerificationData,
      );
    } catch (e) {
      debugPrint('iap: redeem threw: $e');
    }
    if (!settled) {
      _events.add(IapEvent(
        IapEventType.error,
        purchase.productID,
        message: 'покупка будет зачислена позже',
      ));
      return;
    }
    if (Platform.isAndroid &&
        ProductIds.consumables.contains(purchase.productID)) {
      try {
        await InAppPurchase.instance
            .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
            .consumePurchase(purchase);
      } catch (e) {
        // Grant already happened server-side; consumption retries via the
        // redelivery on next launch (redeem then dedupes as ALREADY_REDEEMED).
        debugPrint('iap: consume failed: $e');
      }
    }
    await _completeQuietly(purchase);
    _events.add(IapEvent(
      purchase.status == PurchaseStatus.restored
          ? IapEventType.restoredGranted
          : IapEventType.granted,
      purchase.productID,
    ));
  }

  Future<void> _completeQuietly(PurchaseDetails purchase) async {
    if (!purchase.pendingCompletePurchase) return;
    try {
      await InAppPurchase.instance.completePurchase(purchase);
    } catch (e) {
      debugPrint('iap: completePurchase failed: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _events.close();
  }
}
