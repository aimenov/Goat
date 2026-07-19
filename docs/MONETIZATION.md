# MONETIZATION — AdMob + IAP runbook

How ads and in-app purchases are wired, what the developer must set up in the
consoles before a store release, and the compliance checklist for Google Play
(now) and the App Store (later). Code map: `app/lib/core/services/ads/`,
`app/lib/core/services/iap/`, `app/lib/core/monetization.dart`; server side:
`POST /iap/redeem`, `POST /ads/reward` in `packages/server/src/routes/economy.ts`.

Design philosophy: revenue > 0, never annoy. No banners, nothing mid-game, no
unskippable placements. One interstitial trigger only — leaving to the lobby
from the game-over screen, capped (≥3 games played ever, ≥2 games since the
last one, ≥90 s apart). Rewarded ads are strictly opt-in («Удвоить 🥬 за
рекламу»). Remove-ads buyers never see interstitials but keep the rewarded
option.

---

## 1. Accounts & AdMob console setup

1. Create an AdMob account (same Google account as Play Console is easiest).
2. Register the **Android app** (`com.goatgame.goat_app`). Later, the iOS app.
3. Create **two ad units** for the Android app:
   - Interstitial — suggested name `game_exit`
   - Rewarded — suggested name `reward_double`
4. Where each ID goes:

   | ID | Where |
   |---|---|
   | App ID `ca-app-pub-…~…` | `app/android/app/src/main/AndroidManifest.xml`, `com.google.android.gms.ads.APPLICATION_ID` meta-data (the Google TEST app id `ca-app-pub-3940256099942544~3347511713` is committed there now) |
   | Interstitial unit id | `--dart-define=GOAT_AD_INTERSTITIAL_ANDROID=ca-app-pub-…/…` |
   | Rewarded unit id | `--dart-define=GOAT_AD_REWARDED_ANDROID=ca-app-pub-…/…` |
   | iOS later | `GADApplicationIdentifier` in Info.plist + `GOAT_AD_INTERSTITIAL_IOS` / `GOAT_AD_REWARDED_IOS` |

   Release build example:

   ```
   flutter build appbundle --release \
     --dart-define=GOAT_SERVER=https://<server> \
     --dart-define=GOAT_AD_INTERSTITIAL_ANDROID=ca-app-pub-XXXX/YYYY \
     --dart-define=GOAT_AD_REWARDED_ANDROID=ca-app-pub-XXXX/ZZZZ
   ```

   Debug builds default to Google's canonical **test** units (safe, real
   rendering, zero policy risk). A **release** build without the dart-defines
   fails closed: that ad format simply never loads. Dev escape hatch:
   `--dart-define=GOAT_ADS=off` disables ads entirely even on a device.
5. In AdMob → Privacy & messaging, **publish a GDPR (EU consent) message**
   and, if targeting US states, a US state message. The app runs the UMP flow
   on lobby entry (`ads_service_mobile.dart`); without a published message
   EEA users get no form and `canRequestAds` stays false there.

## 2. app-ads.txt

Host `https://<developer-website>/app-ads.txt` containing the line AdMob shows
under Account → app-ads.txt (shape:
`google.com, pub-XXXXXXXXXXXXXXXX, DIRECT, f08c47fec0942fa0`). The domain must
match the developer website in the Play listing. Not launch-blocking, but some
demand won't serve without it — set it up early.

## 3. AdMob policy notes (why this design is compliant)

- Interstitial only at a natural break: after the game fully ended and the
  user chose to exit. Never at app launch, never mid-game, never before a
  rematch, always closable.
- Rewarded is opt-in behind a clearly labeled button; reward delivery is
  server-side (`/ads/reward`, per-day cap of 5).
- Test devices: register your hardware in AdMob → Settings → Test devices so
  real units serve test ads during pre-release checks. `MobileAds.instance
  .openAdInspector` can be exposed behind a debug menu if needed.
- UMP re-testing: `ConsentDebugSettings(debugGeography: …Eea)` is already
  attached in debug builds; `ConsentInformation.instance.reset()` re-arms the
  form.

## 4. Google Play Console

- **Data safety form**: declare AdMob's collection (device/ad identifiers,
  coarse location, app interaction — copy the current list from Google's
  published "AdMob data disclosure" page, it changes) plus our own server
  data: device-generated guest id, nickname, gameplay stats, purchase tokens.
- **Content rating questionnaire**: card game. **No real-money gambling, no
  simulated gambling** — капуста is a reward/cosmetic currency, never wagered
  on an outcome; answer the gambling questions "no". (If a future mode lets
  players stake coins on games, that flips to "simulated gambling" and raises
  the rating — avoid.)
- **Target audience**: 13+ (or 18+), **not** children — stays out of the
  Families policy which restricts ad SDKs and personalization. No
  child-appealing claims in the listing.
- **Ads declaration**: "contains ads" = yes. In-app purchases declared.
- **IAP products** (Monetize → Products): create with EXACTLY these ids —

  | Product id | Type | Price | Grants (server-side) |
  |---|---|---|---|
  | `goat.remove_ads` | non-consumable | $2.49 | removeAds |
  | `goat.coins.small` | consumable | $0.99 | 500 🥬 |
  | `goat.coins.medium` | consumable | $2.49 | 1500 🥬 |
  | `goat.coins.large` | consumable | $4.99 | 4000 🥬 |
  | `goat.cardback.golden` | non-consumable | $1.49 | back_golden_goat |
  | `goat.table.cabbage` | non-consumable | $1.49 | felt_cabbage |

  Grants live in `packages/shared/src/economy.ts` (IAP_PRODUCTS) — the client
  never decides amounts.
- **Testing IAP**: products only appear in `queryProductDetails` after the
  app is published to a testing track (internal testing is enough), signed
  with the upload key. Add tester accounts under Play Console → Settings →
  License testing: their purchases use a test card (no charge, instant
  refunds available). **Explicitly test the coin-pack repurchase loop** —
  buy `goat.coins.small` twice in a row; the second must succeed (verifies
  the manual consume in `iap_service_mobile.dart`).

## 5. Privacy policy (required by both stores + GDPR)

Host a page (URL goes into both consoles) covering:

- What we collect: device-generated guest id, nickname, gameplay statistics,
  purchase receipts (on our server); Google AdMob: advertising identifiers,
  IP, coarse location (link Google's partner-sites policy).
- Why: gameplay/leaderboards, purchase delivery, advertising.
- Consent & withdrawal: the UMP consent form on first launch in applicable
  regions; «Настройки конфиденциальности рекламы» in the shop screen
  re-opens it.
- Retention and deletion contact: **asatechnoltd@gmail.com**.
- Children: the game is not directed at children under 13.

## 6. App Store (later, when a Mac exists)

- Info.plist: `GADApplicationIdentifier`, `GADDelayAppMeasurementInit`, and
  the **current** `SKAdNetworkItems` list copied fresh from the AdMob iOS
  docs (it changes over time).
- **ATT stance v1: do NOT prompt.** No IDFA → SDK serves non-personalized
  ads automatically, no `NSUserTrackingUsageDescription`, simpler review.
  Cost: lower eCPM (often 30–50%). Revisit once revenue data exists (AdMob's
  IDFA explainer via UMP can chain the ATT prompt later).
- App Privacy nutrition labels: mirror the Play data-safety answers;
  "Identifiers → used for advertising" only if ATT/IDFA is ever adopted.
- IAP products in App Store Connect with the SAME ids; StoreKit
  configuration file for simulator testing, then sandbox testers.
- «Восстановить покупки» is a visible button in the shop (guideline 3.1.1) —
  already implemented.

## 7. Server verification roadmap

- **v1 (current)**: `/iap/redeem` trusts the client's purchase token —
  `TrustingVerifier` logs every grant and the `iap_receipts` table dedupes by
  (platform, token), so a token can only ever be redeemed once. Risk: forged
  tokens — acceptable at launch scale; monitor grant logs. Rewarded ads are
  client-trusted too, bounded by the server cap (5/day) and the 15-minute
  pendingDouble TTL.
- **v2**: real receipt verification behind the existing `IapVerifier` seam —
  Google Play Developer API `purchases.products.get` (service-account JSON) +
  Apple App Store Server API (verify the signed JWS transaction). Add Play
  RTDN (via Pub/Sub) and App Store Server Notifications v2 to handle refunds
  and revocations (revoke removeAds / claw back coins — the client currently
  never downgrades removeAds on its own, by design). Rewarded hardening:
  AdMob server-side verification (SSV) callbacks.

## 8. Client behavior reference

- **Ads init** runs on first lobby build (never over login or the table);
  UMP form → `canRequestAds` → SDK init → preload rewarded + interstitial
  with 5/10/30/60 s load-failure backoff.
- **Interstitial policy** (all must hold): game-over exit trigger only ·
  service available · !removeAds · ≥3 games finished ever · ≥2 since the last
  interstitial · ≥90 s since the last · one preloaded. Counters live in
  SharedPreferences (`ads.gamesFinishedTotal`, `ads.gamesSinceInterstitial`,
  `ads.lastInterstitialAtMs`).
- **IAP flow**: purchase-stream listener attaches at app start (catches
  store redeliveries), redeem-then-acknowledge ordering — the server grant
  must succeed BEFORE `completePurchase`/consume, otherwise the purchase is
  left pending for the store to redeliver (Play auto-refunds unacknowledged
  purchases after ~3 days, which is the correct failure mode).
- **Web/desktop**: both plugins are isolated behind `dart.library.io`
  conditional imports + runtime platform checks; `flutter build web` compiles
  neither. Every monetization surface hides when its hook provider is null.

## 9. Release checklist

- [ ] Real AdMob App ID in AndroidManifest (replace the committed TEST id).
- [ ] Real ad unit ids passed via `--dart-define` in the release command.
- [ ] `GOAT_ADS` NOT set to off.
- [ ] GDPR (+US) consent message published in AdMob.
- [ ] app-ads.txt live on the listed developer domain.
- [ ] IAP products created & active; repurchase loop tested on the internal
      track with a license-tester account.
- [ ] Data safety + content rating (no gambling) + ads declaration submitted.
- [ ] Privacy policy URL live (contact: asatechnoltd@gmail.com).
- [ ] Test devices registered; a full test pass: 3 games → exit → test
      interstitial; «Удвоить 🥬» → rewarded → balance doubles once.
