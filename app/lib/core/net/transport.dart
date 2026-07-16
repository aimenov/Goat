/// Minimal Colyseus 0.17 transport — Dart port of the server repo's
/// `packages/server/test/miniClient.ts` (keep the two in sync).
///
/// Wire format (verified against @colyseus/core 0.17):
///   join:      POST /matchmake/{method}/{roomName} {options}
///              → {name, sessionId, roomId, processId}
///   connect:   ws://host/{processId}/{roomId}?sessionId=S[&reconnectionToken=T]
///   handshake: server → [10][len][token utf8][len][serializerId utf8][...]
///              client → [10]
///   data:      [13][msgpack type][msgpack payload]   (both directions)
///   ping:      server → [18], client replies [18]
///   leave:     client → [12]; consented close code = 4000
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:web_socket_channel/web_socket_channel.dart';

const _joinRoom = 10;
const _leaveRoom = 12;
const _roomData = 13;
const _ping = 18;

class SeatReservation {
  final String name;
  final String sessionId;
  final String roomId;
  final String processId;

  SeatReservation.fromJson(Map<String, dynamic> json)
      : name = json['name'] as String,
        sessionId = json['sessionId'] as String,
        roomId = json['roomId'] as String,
        processId = json['processId'] as String;
}

class GoatTransportException implements Exception {
  final String message;
  GoatTransportException(this.message);
  @override
  String toString() => 'GoatTransportException: $message';
}

/// One joined room connection.
class GameRoom {
  final String httpEndpoint;
  final SeatReservation reservation;

  WebSocketChannel? _channel;
  final _messages = StreamController<(String, Object?)>.broadcast();
  final _joined = Completer<void>();
  final _closed = Completer<int>();
  String reconnectionToken = '';
  String serializerId = '';

  GameRoom(this.httpEndpoint, this.reservation);

  String get roomId => reservation.roomId;
  String get sessionId => reservation.sessionId;

  /// Typed message stream: (type, payload). Payloads are msgpack-decoded
  /// maps/lists/scalars.
  Stream<(String, Object?)> get messages => _messages.stream;

  /// Fires once when the connection closes (any reason), with the close code.
  Future<int> get onClose => _closed.future;

  Future<void> connect({String? reconnectionToken}) {
    final wsEndpoint = httpEndpoint.replaceFirst(RegExp('^http'), 'ws');
    final params = {'sessionId': reservation.sessionId};
    if (reconnectionToken != null) params['reconnectionToken'] = reconnectionToken;
    final query = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
    final url = '$wsEndpoint/${reservation.processId}/${reservation.roomId}?$query';

    final channel = WebSocketChannel.connect(Uri.parse(url));
    _channel = channel;
    channel.stream.listen(
      (data) => _onFrame(Uint8List.fromList((data as List<int>))),
      onError: (Object e) {
        if (!_joined.isCompleted) _joined.completeError(GoatTransportException('$e'));
      },
      onDone: () {
        final code = channel.closeCode ?? 1006;
        if (!_joined.isCompleted) {
          _joined.completeError(GoatTransportException('closed before join (code $code)'));
        }
        if (!_closed.isCompleted) _closed.complete(code);
        _messages.close();
      },
    );
    return _joined.future;
  }

  void _onFrame(Uint8List data) {
    final code = data[0];
    switch (code) {
      case _joinRoom:
        // [10][len][token utf8][len][serializerId utf8][handshake...]
        var offset = 1;
        final tokenLen = data[offset++];
        final token = utf8.decode(data.sublist(offset, offset + tokenLen));
        offset += tokenLen;
        final serializerLen = data[offset++];
        serializerId = utf8.decode(data.sublist(offset, offset + serializerLen));
        reconnectionToken = '${reservation.roomId}:$token';
        _send(Uint8List.fromList([_joinRoom]));
        if (!_joined.isCompleted) _joined.complete();
      case _roomData:
        final values = _unpackMultiple(data.sublist(1), 2);
        if (values.length == 2) {
          _messages.add(('${values[0]}', values[1]));
        }
      case _ping:
        _send(Uint8List.fromList([_ping]));
    }
  }

  /// Decode up to [max] consecutive msgpack values from [bytes].
  List<Object?> _unpackMultiple(Uint8List bytes, int max) {
    final values = <Object?>[];
    final deserializer = msgpack.Deserializer(bytes);
    for (var i = 0; i < max; i++) {
      try {
        values.add(deserializer.decode());
      } catch (_) {
        break;
      }
    }
    return values;
  }

  void send(String type, Object? payload) {
    final builder = BytesBuilder();
    builder.addByte(_roomData);
    builder.add(msgpack.serialize(type));
    builder.add(msgpack.serialize(payload));
    _send(builder.toBytes());
  }

  void _send(Uint8List bytes) => _channel?.sink.add(bytes);

  /// Consented leave — the server will not hold the seat.
  Future<void> leave() async {
    _send(Uint8List.fromList([_leaveRoom]));
    await _closed.future.timeout(const Duration(seconds: 3), onTimeout: () => 0);
  }

  /// Hard close (e.g. app going to background) — the server holds the seat
  /// for the reconnection window.
  void drop() {
    _channel?.sink.close();
  }
}

class GoatClient {
  final String endpoint;
  final http.Client _http;

  GoatClient(this.endpoint, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  Future<SeatReservation> _matchmake(String method, String roomName, Map<String, Object?> options) async {
    final res = await _http.post(
      Uri.parse('$endpoint/matchmake/$method/$roomName'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(options),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw GoatTransportException('matchmake $method failed: ${body['error'] ?? res.statusCode}');
    }
    return SeatReservation.fromJson(body);
  }

  Future<GameRoom> joinOrCreate(String roomName, Map<String, Object?> options) async {
    final room = GameRoom(endpoint, await _matchmake('joinOrCreate', roomName, options));
    await room.connect();
    return room;
  }

  Future<GameRoom> create(String roomName, Map<String, Object?> options) async {
    final room = GameRoom(endpoint, await _matchmake('create', roomName, options));
    await room.connect();
    return room;
  }

  Future<GameRoom> joinById(String roomId, Map<String, Object?> options) async {
    final room = GameRoom(endpoint, await _matchmake('joinById', roomId, options));
    await room.connect();
    return room;
  }

  /// [reconnectionToken] format: "{roomId}:{token}".
  Future<GameRoom> reconnect(String reconnectionToken) async {
    final parts = reconnectionToken.split(':');
    final reservation = await _matchmake('reconnect', parts[0], {'reconnectionToken': parts[1]});
    final room = GameRoom(endpoint, reservation);
    await room.connect(reconnectionToken: parts[1]);
    return room;
  }
}
