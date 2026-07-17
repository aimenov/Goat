/// App session: server endpoint, guest identity, and the active room.
library;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider is not exported from the main library in Riverpod 3.
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game/game_controller.dart';
import 'net/api.dart';
import 'net/transport.dart';

/// Server endpoint. `--dart-define=GOAT_SERVER=...` always wins (required for
/// real devices); otherwise: web/desktop talk to localhost directly, the
/// Android emulator reaches the host via 10.0.2.2.
String defaultServerEndpoint() {
  const defined = String.fromEnvironment('GOAT_SERVER');
  if (defined.isNotEmpty) return defined;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:2568';
  }
  return 'http://localhost:2568';
}

final serverEndpointProvider = StateProvider<String>((ref) => defaultServerEndpoint());

final apiProvider = Provider<GoatApi>((ref) => GoatApi(ref.watch(serverEndpointProvider)));
final clientProvider = Provider<GoatClient>((ref) => GoatClient(ref.watch(serverEndpointProvider)));

class Identity {
  final String token;
  final String playerId;
  final String nickname;
  const Identity({required this.token, required this.playerId, required this.nickname});
}

class IdentityController extends AsyncNotifier<Identity?> {
  @override
  Future<Identity?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final playerId = prefs.getString('playerId');
    final nickname = prefs.getString('nickname');
    if (token == null || playerId == null || nickname == null) return null;
    return Identity(token: token, playerId: playerId, nickname: nickname);
  }

  /// Registers (or re-registers) a guest identity with the chosen nickname.
  Future<Identity> login(String nickname) async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString('deviceId');
    if (deviceId == null) {
      final rnd = Random.secure();
      deviceId = List.generate(24, (_) => '0123456789abcdef'[rnd.nextInt(16)]).join();
      await prefs.setString('deviceId', deviceId);
    }
    final api = ref.read(apiProvider);
    final guest = await api.guestAuth(deviceId, nickname);
    await prefs.setString('token', guest.token);
    await prefs.setString('playerId', guest.playerId);
    await prefs.setString('nickname', guest.nickname);
    final identity = Identity(token: guest.token, playerId: guest.playerId, nickname: guest.nickname);
    state = AsyncData(identity);
    return identity;
  }
}

final identityProvider = AsyncNotifierProvider<IdentityController, Identity?>(IdentityController.new);

/// Owns the lifecycle of the joined room and hooks it to the game controller.
class RoomSession extends Notifier<GameRoom?> {
  @override
  GameRoom? build() => null;

  Map<String, Object?> _joinOptions() {
    final identity = ref.read(identityProvider).value;
    return {
      if (identity != null) 'token': identity.token,
      if (identity != null) 'nickname': identity.nickname,
    };
  }

  Future<void> createRoom({required int playerCount, required int scoreLimit, required int turnSeconds, String? name}) async {
    final room = await ref.read(clientProvider).create('goat', {
      ..._joinOptions(),
      'playerCount': playerCount,
      'scoreLimit': scoreLimit,
      'turnSeconds': turnSeconds,
      if (name != null && name.isNotEmpty) 'name': name,
    });
    _adopt(room);
  }

  Future<void> joinRoom(String roomId) async {
    final room = await ref.read(clientProvider).joinById(roomId, _joinOptions());
    _adopt(room);
  }

  Future<void> quickJoin() async {
    final room = await ref.read(clientProvider).joinOrCreate('goat', _joinOptions());
    _adopt(room);
  }

  Future<void> reconnect() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('reconnectionToken');
    if (token == null) throw GoatTransportException('Нет сохранённой игры');
    final GameRoom room;
    try {
      room = await ref.read(clientProvider).reconnect(token);
    } on GoatTransportException {
      // Dead token / disposed room: the server refused the matchmake, so
      // retrying with the same token would fail identically — drop it.
      await prefs.remove('reconnectionToken');
      throw GoatTransportException('Стол уже закрыт');
    }
    _adopt(room);
  }

  void _adopt(GameRoom room) {
    state = room;
    ref.read(gameControllerProvider.notifier).attach(room);
    SharedPreferences.getInstance().then((prefs) => prefs.setString('reconnectionToken', room.reconnectionToken));
  }

  Future<void> leave() async {
    final room = state;
    state = null;
    ref.read(gameControllerProvider.notifier).detach();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('reconnectionToken');
    await room?.leave();
  }
}

final roomSessionProvider = NotifierProvider<RoomSession, GameRoom?>(RoomSession.new);
