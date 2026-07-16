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

/// Player meta-profile: lifetime stats + unlocked achievement ids.
class PlayerProfile {
  final ProfileStats stats;
  final Set<String> unlocked;

  const PlayerProfile({this.stats = const ProfileStats(), this.unlocked = const {}});

  /// Defensive: any missing/odd field collapses to zeros / empty.
  factory PlayerProfile.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'];
    final achievements = json['achievements'];
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
    );
  }
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
}
