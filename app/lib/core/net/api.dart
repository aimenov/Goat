/// Plain HTTP endpoints: guest auth and the open-room list.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

class GuestIdentity {
  final String token;
  final String playerId;
  final String nickname;
  GuestIdentity({required this.token, required this.playerId, required this.nickname});
}

class RoomListing {
  final String roomId;
  final int clients;
  final int maxClients;
  final String name;
  final int playerCount;
  final int scoreLimit;
  final int turnSeconds;
  final bool started;

  RoomListing.fromJson(Map<String, dynamic> json)
      : roomId = json['roomId'] as String,
        clients = (json['clients'] as num?)?.toInt() ?? 0,
        maxClients = (json['maxClients'] as num?)?.toInt() ?? 0,
        name = (json['metadata']?['name'] as String?) ?? 'Козёл',
        playerCount = (json['metadata']?['playerCount'] as num?)?.toInt() ?? 4,
        scoreLimit = (json['metadata']?['scoreLimit'] as num?)?.toInt() ?? 24,
        turnSeconds = (json['metadata']?['turnSeconds'] as num?)?.toInt() ?? 30,
        started = (json['metadata']?['started'] as bool?) ?? false;
}

/// Tolerant int read: any non-numeric wire value collapses to [fallback].
int _asInt(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;

class ProfileStats {
  final int gamesPlayed;
  final int gamesWon;
  final int goats;
  final int winStreak;

  const ProfileStats({
    this.gamesPlayed = 0,
    this.gamesWon = 0,
    this.goats = 0,
    this.winStreak = 0,
  });
}

/// One daily quest («Задание дня») as the server reports it. Display-only on
/// the client: rewards auto-credit server-side at game end.
class QuestState {
  final String id;
  final String ru;
  final int progress;
  final int target;
  final int reward;
  final bool claimed;

  const QuestState({
    required this.id,
    this.ru = '',
    this.progress = 0,
    this.target = 1,
    this.reward = 0,
    this.claimed = false,
  });

  bool get completed => claimed || progress >= target;

  /// Defensive: any missing/odd field collapses to a harmless default.
  factory QuestState.fromJson(Map<dynamic, dynamic> json) => QuestState(
        id: '${json['id'] ?? ''}',
        ru: '${json['ru'] ?? ''}',
        progress: _asInt(json['progress']),
        target: _asInt(json['target'], 1),
        reward: _asInt(json['reward']),
        claimed: json['claimed'] == true || json['completed'] == true,
      );
}

/// Which cosmetics are active; ids default to the built-in classics.
class EquippedCosmetics {
  final String cardBack;
  final String felt;

  const EquippedCosmetics({this.cardBack = 'back_classic', this.felt = 'felt_classic'});

  factory EquippedCosmetics.fromJson(Map<dynamic, dynamic> json) => EquippedCosmetics(
        cardBack: json['cardBack'] is String ? json['cardBack'] as String : 'back_classic',
        felt: json['felt'] is String ? json['felt'] as String : 'felt_classic',
      );

  EquippedCosmetics copyWith({String? cardBack, String? felt}) => EquippedCosmetics(
        cardBack: cardBack ?? this.cardBack,
        felt: felt ?? this.felt,
      );
}

/// Player meta-profile: lifetime stats, unlocked achievement ids and the
/// economy extension (капуста, rating, quests, cosmetics). EVERY economy
/// field defaults so an older server (or missing endpoint) keeps working
/// with the features dormant.
class PlayerProfile {
  final ProfileStats stats;
  final Set<String> unlocked;
  final int coins;
  final int rating;
  final String? rankId;
  final int dailyStreak;
  final bool dailyClaimable;

  /// Which day the NEXT claim pays (server-computed: a lapsed streak resets
  /// to 1, which [dailyStreak] alone can't tell). 0 = unknown (older server).
  final int nextClaimStreak;
  final int weeklyCoins;
  final List<QuestState> quests;
  final Set<String> ownedCosmetics;
  final EquippedCosmetics equipped;
  final bool removeAds;

  const PlayerProfile({
    this.stats = const ProfileStats(),
    this.unlocked = const {},
    this.coins = 0,
    this.rating = 1000,
    this.rankId,
    this.dailyStreak = 0,
    this.dailyClaimable = false,
    this.nextClaimStreak = 0,
    this.weeklyCoins = 0,
    this.quests = const [],
    this.ownedCosmetics = const {},
    this.equipped = const EquippedCosmetics(),
    this.removeAds = false,
  });

  /// Defensive: any missing/odd field collapses to zeros / empty.
  factory PlayerProfile.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'];
    final achievements = json['achievements'];
    final rank = json['rank'];
    final quests = json['quests'];
    final owned = json['ownedCosmetics'];
    final equipped = json['equipped'];
    return PlayerProfile(
      stats: stats is Map
          ? ProfileStats(
              gamesPlayed: (stats['gamesPlayed'] as num?)?.toInt() ?? 0,
              gamesWon: (stats['gamesWon'] as num?)?.toInt() ?? 0,
              goats: (stats['goats'] as num?)?.toInt() ?? 0,
              winStreak: (stats['winStreak'] as num?)?.toInt() ?? 0,
            )
          : const ProfileStats(),
      unlocked: achievements is List
          ? {
              for (final a in achievements)
                if (a is Map && a['id'] != null) '${a['id']}',
            }
          : const {},
      coins: _asInt(json['coins']),
      rating: _asInt(json['rating'], 1000),
      rankId: rank is Map && rank['id'] != null
          ? '${rank['id']}'
          : (json['rankId'] is String ? json['rankId'] as String : null),
      dailyStreak: _asInt(json['dailyStreak']),
      dailyClaimable: json['dailyClaimable'] == true,
      nextClaimStreak: _asInt(json['nextClaimStreak']),
      weeklyCoins: _asInt(json['weeklyCoins']),
      quests: quests is List
          ? [
              for (final q in quests)
                if (q is Map) QuestState.fromJson(q),
            ]
          : const [],
      ownedCosmetics: owned is List ? {for (final c in owned) '$c'} : const {},
      equipped: equipped is Map
          ? EquippedCosmetics.fromJson(equipped)
          : const EquippedCosmetics(),
      removeAds: json['removeAds'] == true,
    );
  }

  PlayerProfile copyWith({
    ProfileStats? stats,
    Set<String>? unlocked,
    int? coins,
    int? rating,
    Object? rankId = _sentinel,
    int? dailyStreak,
    bool? dailyClaimable,
    int? nextClaimStreak,
    int? weeklyCoins,
    List<QuestState>? quests,
    Set<String>? ownedCosmetics,
    EquippedCosmetics? equipped,
    bool? removeAds,
  }) =>
      PlayerProfile(
        stats: stats ?? this.stats,
        unlocked: unlocked ?? this.unlocked,
        coins: coins ?? this.coins,
        rating: rating ?? this.rating,
        rankId: rankId == _sentinel ? this.rankId : rankId as String?,
        dailyStreak: dailyStreak ?? this.dailyStreak,
        dailyClaimable: dailyClaimable ?? this.dailyClaimable,
        nextClaimStreak: nextClaimStreak ?? this.nextClaimStreak,
        weeklyCoins: weeklyCoins ?? this.weeklyCoins,
        quests: quests ?? this.quests,
        ownedCosmetics: ownedCosmetics ?? this.ownedCosmetics,
        equipped: equipped ?? this.equipped,
        removeAds: removeAds ?? this.removeAds,
      );
}

const _sentinel = Object();

/// One leaderboard row («Доска почёта»).
class LeaderboardEntry {
  final int position;
  final String playerId;
  final String nickname;
  final int rating;
  final int weeklyCoins;

  const LeaderboardEntry({
    this.position = 0,
    this.playerId = '',
    this.nickname = '',
    this.rating = 1000,
    this.weeklyCoins = 0,
  });

  factory LeaderboardEntry.fromJson(Map<dynamic, dynamic> json) => LeaderboardEntry(
        position: _asInt(json['position']),
        playerId: '${json['playerId'] ?? ''}',
        nickname: '${json['nickname'] ?? ''}',
        rating: _asInt(json['rating'], 1000),
        weeklyCoins: _asInt(json['weeklyCoins']),
      );
}

/// Top-50 plus (optionally) the requesting player's own row.
class LeaderboardData {
  final List<LeaderboardEntry> entries;
  final LeaderboardEntry? me;

  const LeaderboardData({this.entries = const [], this.me});
}

/// POST /daily/claim result — a merge payload, not a full profile.
class DailyClaimResult {
  final int amount;
  final int streak;
  final int coins;
  final bool canDouble;

  const DailyClaimResult({
    this.amount = 0,
    this.streak = 0,
    this.coins = 0,
    this.canDouble = false,
  });

  factory DailyClaimResult.fromJson(Map<dynamic, dynamic> json) => DailyClaimResult(
        amount: _asInt(json['amount']),
        streak: _asInt(json['streak']),
        coins: _asInt(json['coins']),
        canDouble: json['canDouble'] == true,
      );
}

/// POST /shop/purchase result: the new balance + owned set.
class PurchaseResult {
  final int coins;
  final Set<String> owned;
  const PurchaseResult({this.coins = 0, this.owned = const {}});
}

/// POST /ads/reward result: the 🥬 amount credited (0 = nothing granted)
/// plus the new balance.
class AdRewardResult {
  final int granted;
  final int coins;
  const AdRewardResult({this.granted = 0, this.coins = 0});
}

/// POST /iap/redeem result. [alreadyRedeemed] marks a 409 replay (restore or
/// stream redelivery): the purchase is settled server-side either way, so the
/// caller may acknowledge it with the store.
class IapRedeemResult {
  final int coins;
  final bool removeAds;
  final Set<String> owned;
  final bool alreadyRedeemed;
  const IapRedeemResult({
    this.coins = 0,
    this.removeAds = false,
    this.owned = const {},
    this.alreadyRedeemed = false,
  });
}

class GoatApi {
  final String endpoint;
  final http.Client _http;

  GoatApi(this.endpoint, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  Future<GuestIdentity> guestAuth(String deviceId, String nickname) async {
    final res = await _http.post(
      Uri.parse('$endpoint/auth/guest'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'deviceId': deviceId, 'nickname': nickname}),
    );
    if (res.statusCode >= 400) throw Exception('guest auth failed: ${res.statusCode}');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return GuestIdentity(
      token: body['token'] as String,
      playerId: body['playerId'] as String,
      nickname: body['nickname'] as String,
    );
  }

  /// Stats + unlocked achievements. A fresh player (or an older server
  /// without the endpoint) answers 404 — treated as an empty profile.
  Future<PlayerProfile> profile(String playerId) async {
    final res = await _http.get(Uri.parse('$endpoint/profile/$playerId'));
    if (res.statusCode == 404) return const PlayerProfile();
    if (res.statusCode >= 400) throw Exception('profile failed: ${res.statusCode}');
    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) return const PlayerProfile();
    return PlayerProfile.fromJson(body);
  }

  Future<List<RoomListing>> listRooms() async {
    final res = await _http.get(Uri.parse('$endpoint/rooms'));
    if (res.statusCode >= 400) throw Exception('room list failed: ${res.statusCode}');
    final body = jsonDecode(res.body) as List<dynamic>;
    return body.map((r) => RoomListing.fromJson(r as Map<String, dynamic>)).toList();
  }

  // -------------------------------------------------------------- economy
  //
  // Every endpoint below may be missing on an older server: 404 means
  // "feature absent" and returns an empty/null result so the UI stays
  // dormant; other >=400 codes throw with a readable RU message.

  Map<String, String> _bearer(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  /// Maps a rejected economy response to a human-readable exception.
  Never _fail(http.Response res, String what) {
    String? code;
    try {
      final body = jsonDecode(res.body) as Map;
      // The server's ctx.error serializes as {"code": ...}; accept a legacy
      // {"error": ...} shape too.
      code = (body['code'] ?? body['error'])?.toString();
    } catch (_) {
      // non-JSON body — fall through to the status-code mapping
    }
    final message = switch (code) {
      'ALREADY_CLAIMED' => 'Бонус уже получен',
      'ALREADY_OWNED' => 'Уже куплено',
      'ALREADY_REDEEMED' => 'Покупка уже учтена',
      'NOTHING_TO_DOUBLE' => 'Удвоение уже недоступно',
      'INSUFFICIENT_FUNDS' => 'Не хватает капусты',
      _ => switch (res.statusCode) {
          402 => 'Не хватает капусты',
          403 => 'Этот предмет так не продаётся',
          409 => 'Уже получено',
          429 => 'Лимит рекламы на сегодня исчерпан',
          _ => '$what: ${res.statusCode}',
        },
    };
    throw Exception(message);
  }

  /// Top-50 board for [scope] ('weekly' | 'alltime'); a Bearer [token] lets
  /// the server add the caller's own row.
  Future<LeaderboardData> leaderboard(String scope, {String? token}) async {
    final res = await _http.get(
      Uri.parse('$endpoint/leaderboard?scope=$scope'),
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode == 404) return const LeaderboardData();
    if (res.statusCode >= 400) _fail(res, 'leaderboard failed');
    final body = jsonDecode(res.body);
    if (body is! Map) return const LeaderboardData();
    final entries = body['entries'];
    final me = body['me'];
    return LeaderboardData(
      entries: entries is List
          ? [
              for (final e in entries)
                if (e is Map) LeaderboardEntry.fromJson(e),
            ]
          : const [],
      me: me is Map ? LeaderboardEntry.fromJson(me) : null,
    );
  }

  /// Claims today's bonus. Null = feature absent on this server.
  Future<DailyClaimResult?> claimDaily(String token) async {
    final res = await _http.post(
      Uri.parse('$endpoint/daily/claim'),
      headers: _bearer(token),
    );
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 400) _fail(res, 'daily claim failed');
    final body = jsonDecode(res.body);
    return body is Map ? DailyClaimResult.fromJson(body) : null;
  }

  /// Buys a cosmetic for капусту. Null = feature absent on this server.
  Future<PurchaseResult?> purchase(String token, String itemId) async {
    final res = await _http.post(
      Uri.parse('$endpoint/shop/purchase'),
      headers: _bearer(token),
      body: jsonEncode({'itemId': itemId}),
    );
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 400) _fail(res, 'purchase failed');
    final body = jsonDecode(res.body);
    if (body is! Map) return null;
    final owned = body['owned'];
    return PurchaseResult(
      coins: _asInt(body['coins']),
      owned: owned is List ? {for (final c in owned) '$c'} : const {},
    );
  }

  /// Equips an owned (or default) cosmetic. Null = feature absent.
  Future<EquippedCosmetics?> equip(String token, String itemId) async {
    final res = await _http.post(
      Uri.parse('$endpoint/shop/equip'),
      headers: _bearer(token),
      body: jsonEncode({'itemId': itemId}),
    );
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 400) _fail(res, 'equip failed');
    final body = jsonDecode(res.body);
    if (body is! Map) return null;
    final equipped = body['equipped'];
    return equipped is Map ? EquippedCosmetics.fromJson(equipped) : null;
  }

  /// Redeems a watched rewarded ad ([kind]: 'doubleGame' | 'doubleDaily').
  /// Null = feature absent on this server.
  Future<AdRewardResult?> adReward(String token, String kind) async {
    final res = await _http.post(
      Uri.parse('$endpoint/ads/reward'),
      headers: _bearer(token),
      body: jsonEncode({'kind': kind}),
    );
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 400) _fail(res, 'ad reward failed');
    final body = jsonDecode(res.body);
    if (body is! Map) return null;
    return AdRewardResult(
      // The server sends the granted amount; tolerate a legacy boolean too.
      granted: body['granted'] == true ? 1 : _asInt(body['granted']),
      coins: _asInt(body['coins']),
    );
  }

  /// Redeems a store purchase server-side. Null = not settled (older server
  /// without the endpoint, or unknown product) — the caller must NOT
  /// acknowledge the purchase so the store redelivers it later. A 409
  /// ALREADY_REDEEMED replay counts as settled.
  Future<IapRedeemResult?> iapRedeem(
    String token, {
    required String platform,
    required String productId,
    required String purchaseToken,
  }) async {
    final res = await _http.post(
      Uri.parse('$endpoint/iap/redeem'),
      headers: _bearer(token),
      body: jsonEncode({
        'platform': platform,
        'productId': productId,
        'token': purchaseToken,
      }),
    );
    if (res.statusCode == 404) return null;
    if (res.statusCode == 409) {
      return const IapRedeemResult(alreadyRedeemed: true);
    }
    if (res.statusCode >= 400) _fail(res, 'iap redeem failed');
    final body = jsonDecode(res.body);
    if (body is! Map) return null;
    final owned = body['owned'];
    return IapRedeemResult(
      coins: _asInt(body['coins']),
      removeAds: body['removeAds'] == true,
      owned: owned is List ? {for (final c in owned) '$c'} : const {},
    );
  }
}
