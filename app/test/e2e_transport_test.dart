/// E2E gate for the Dart transport + models against a REAL server.
/// Start the server first:  npm run dev   (or: npx tsx packages/server/src/index.ts)
/// Skips itself when no server is listening on localhost:2568.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:goat_app/core/game/models.dart';
import 'package:goat_app/core/net/api.dart';
import 'package:goat_app/core/net/transport.dart';

const endpoint = String.fromEnvironment(
  'GOAT_E2E_SERVER',
  defaultValue: 'http://localhost:2568',
);

/// Probes the endpoint and verifies it really is the Goat server (another
/// project's dev server sometimes squats on the port and answers /health).
/// Returns null when the server looks right, otherwise a human-readable
/// mismatch description to put in the skip message.
Future<String?> serverUp() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final healthReq = await client.getUrl(Uri.parse('$endpoint/health'));
    final healthRes = await healthReq.close().timeout(
      const Duration(seconds: 2),
    );
    await healthRes.drain<void>();
    if (healthRes.statusCode != 200) {
      return '/health answered ${healthRes.statusCode}';
    }
    // /health alone is not enough — also require a Goat-shaped guest auth.
    final authReq = await client.postUrl(Uri.parse('$endpoint/auth/guest'));
    authReq.headers.contentType = ContentType.json;
    authReq.write(
      jsonEncode({'deviceId': 'e2e-probe-000000', 'nickname': 'probe'}),
    );
    final authRes = await authReq.close().timeout(const Duration(seconds: 2));
    final body = await authRes
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 2));
    if (authRes.statusCode != 200) {
      return '/auth/guest answered ${authRes.statusCode}';
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['playerId'] == null) {
      final shape = decoded is Map
          ? 'keys: ${decoded.keys.join(', ')}'
          : '${decoded.runtimeType}';
      return "/auth/guest response has no 'playerId' ($shape) — "
          'not the Goat server';
    }
    return null;
  } catch (e) {
    return 'probe failed ($e)';
  } finally {
    client.close(force: true);
  }
}

class TestPlayer {
  final GameRoom room;
  Map<String, Object?>? view;
  int viewSeq = -1;
  int seat = -1;
  final acks = <Map<String, Object?>>[];
  final events = <Map<String, Object?>>[];

  TestPlayer(this.room) {
    room.messages.listen((message) {
      final (type, payload) = message;
      final m = asMap(payload);
      switch (type) {
        case 'snapshot':
          view = asMap(m['view']);
          viewSeq = (m['seq'] as num).toInt();
          seat = (view!['seat'] as num).toInt();
        case 'ack':
          acks.add(m);
        case 'event':
          events.add(m);
      }
    });
  }

  bool get gameEnded => events.any((e) => e['type'] == 'gameEnded');

  Map<String, Object?>? get lastTurn =>
      events.lastWhere((e) => e['type'] == 'turn', orElse: () => const {}).isEmpty
          ? null
          : events.lastWhere((e) => e['type'] == 'turn');

  void playFromView(String actionId) {
    final legal = asMap(view!['legal']);
    final hand = asIntList(view!['myHand']);
    switch ('${legal['kind']}') {
      case 'lead':
        room.send('intent', {
          'type': 'lead',
          'actionId': actionId,
          'cards': [hand.first],
        });
      case 'respond':
        final canBeat = legal['canBeat'] == true;
        if (canBeat) {
          // simple greedy over the beat matrix (k is small; server re-validates)
          final matrix = (legal['beatMatrix'] as Map).map((k, v) => MapEntry(int.parse('$k'), asIntList(v)));
          final used = <int>{};
          final pairs = <Map<String, int>>[];
          var ok = true;
          for (final entry in matrix.entries) {
            final candidate = entry.value.where((c) => !used.contains(c)).firstOrNull;
            if (candidate == null) {
              ok = false;
              break;
            }
            used.add(candidate);
            pairs.add({'target': entry.key, 'card': candidate});
          }
          if (ok) {
            room.send('intent', {'type': 'beat', 'actionId': actionId, 'pairs': pairs});
            return;
          }
        }
        final k = (legal['discardCount'] as num).toInt();
        room.send('intent', {'type': 'discard', 'actionId': actionId, 'cards': hand.take(k).toList()});
      case 'leaderDecision':
        room.send('intent', {'type': 'endTrick', 'actionId': actionId});
    }
  }
}

Future<void> until(bool Function() cond, String what, {int ms = 10000}) async {
  final t0 = DateTime.now();
  while (!cond()) {
    if (DateTime.now().difference(t0).inMilliseconds > ms) {
      throw TimeoutException('waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
}

void main() {
  test('Dart transport plays a full 2p game against the real server', () async {
    final mismatch = await serverUp();
    if (mismatch != null) {
      markTestSkipped(
        'no Goat server on $endpoint ($mismatch) — start it with `npm run dev`',
      );
      return;
    }

    final api = GoatApi(endpoint);
    final identity = await api.guestAuth('e2e-device-000001', 'Дарт');
    expect(identity.token.length, greaterThan(20));

    final client = GoatClient(endpoint);
    final roomA = await client.create('goat', {
      'token': identity.token,
      'playerCount': 2,
      'scoreLimit': 24,
      'turnSeconds': 15,
    });
    final roomB = await client.joinById(roomA.roomId, {'nickname': 'Второй'});
    final a = TestPlayer(roomA);
    final b = TestPlayer(roomB);

    roomA.send('intent', {'type': 'ready', 'ready': true});
    roomB.send('intent', {'type': 'ready', 'ready': true});
    await until(() => a.view != null || b.view != null, 'game start');
    roomA.send('intent', {'type': 'resync', });
    roomB.send('intent', {'type': 'resync', });
    await until(() => a.view != null && b.view != null, 'both snapshots');

    expect(asIntList(a.view!['myHand']).length, 6);
    expect(asIntList(b.view!['myHand']).length, 6);

    var moves = 0;
    while (!a.gameEnded && moves < 2000) {
      final turn = a.lastTurn;
      if (turn == null) {
        await Future<void>.delayed(const Duration(milliseconds: 15));
        continue;
      }
      final turnSeq = (turn['seq'] as num).toInt();
      final mover = (turn['seat'] as num).toInt() == a.seat ? a : b;
      await until(
        () => a.gameEnded || (mover.viewSeq >= turnSeq && mover.view!['legal'] != null),
        'snapshot for turn seq $turnSeq',
      );
      if (a.gameEnded) break;
      final ackCount = mover.acks.length;
      mover.playFromView('e2e-$moves');
      await until(() => mover.acks.length > ackCount, 'ack $moves');
      final ack = mover.acks.last;
      // NOT_YOUR_TURN can happen when a fresh turn event lands between reading
      // the view and sending — a test-client race, not a server bug. Retry.
      if (ack['ok'] != true && ack['error'] == 'NOT_YOUR_TURN') continue;
      expect(ack['ok'], true, reason: 'move $moves rejected: ${ack['error']}');
      moves++;
    }

    expect(a.gameEnded, true, reason: 'game did not finish in $moves moves');
    final end = a.events.lastWhere((e) => e['type'] == 'gameEnded');
    expect(asIntList(end['goats']), isNotEmpty);

    await roomA.leave();
    await roomB.leave();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
