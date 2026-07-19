/// Web build target (no dart.library.io): ads stay a no-op and the
/// google_mobile_ads plugin is never compiled.
library;

import 'ads_service.dart';

AdsService createAdsService() => NoopAdsService();
