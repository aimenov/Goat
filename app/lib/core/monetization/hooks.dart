/// Monetization seams. Workstream C1 ships only the hooks: every ad/IAP
/// surface watches these providers and self-hides while they are null. The
/// monetization workstream overrides them in main.dart with real
/// implementations backed by google_mobile_ads / in_app_purchase.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows a rewarded ad for [kind] ('doubleGame' | 'doubleDaily') and resolves
/// to whether the user actually watched it through to the reward.
abstract class RewardedAdHook {
  Future<bool> show(String kind);
}

/// Launches the store purchase flow for [productId]; resolves to whether the
/// purchase completed (server redemption included).
abstract class IapHook {
  Future<bool> purchase(String productId);
}

/// Null until the monetization workstream overrides it: ad buttons hidden.
final rewardedAdHookProvider = Provider<RewardedAdHook?>((ref) => null);

/// Null until the monetization workstream overrides it: IAP surfaces hidden.
final iapHookProvider = Provider<IapHook?>((ref) => null);
