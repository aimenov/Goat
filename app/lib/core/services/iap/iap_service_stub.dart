/// Web build target (no dart.library.io): purchases stay a no-op and the
/// in_app_purchase plugin is never compiled.
library;

import 'iap_service.dart';

IapService createIapService(RedeemFn redeem) => NoopIapService();
