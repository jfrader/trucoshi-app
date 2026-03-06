import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:trucoshi_app/platform/platform_caps.dart';
import 'package:trucoshi_app/services/auth_service.dart';
import 'package:trucoshi_app/services/ws/ws_service.dart';

class _FakeWebSocketSink extends DelegatingStreamSink<Object?>
    implements WebSocketSink {
  _FakeWebSocketSink(this._controller) : super(_controller.sink);

  final StreamController<Object?> _controller;

  int? _closeCode;
  String? _closeReason;

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _closeCode = closeCode;
    _closeReason = closeReason;
    await _controller.close();
  }

  int? get closeCode => _closeCode;
  String? get closeReason => _closeReason;
}

class _FakeWebSocketChannel
    with StreamChannelMixin<Object?>
    implements WebSocketChannel {
  _FakeWebSocketChannel();

  final _server = StreamController<Object?>.broadcast();
  final _clientController = StreamController<Object?>.broadcast();
  late final _sink = _FakeWebSocketSink(_clientController);

  @override
  Stream<Object?> get stream => _server.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  String? get protocol => null;

  @override
  int? get closeCode => _sink.closeCode;

  @override
  String? get closeReason => _sink.closeReason;

  @override
  Future<void> get ready => Future.value();

  void serverAddRaw(Object? event) {
    _server.add(event);
  }

  void serverAddJson(Map<String, Object?> frame) {
    _server.add(jsonEncode(frame));
  }

  Future<void> dispose() async {
    await _server.close();
    await _clientController.close();
    await sink.close();
  }
}

void main() {
  testWidgets(
    'WsService tolerates malformed frames and clears decode errors on next good frame',
    (tester) async {
      final auth = AuthService();
      auth.continueAsGuest(displayName: 'Fran');

      final chan = _FakeWebSocketChannel();
      final caps = const PlatformCaps(supportsWsAuthHeaders: true);

      final ws = WsService(
        auth: auth,
        caps: caps,
        channelFactory: (uri, {headers}) => chan,
      );

      await tester.runAsync(() async {
        await ws.connect();
      });

      expect(ws.state, WsConnectionState.connected);
      expect(ws.lastError, isNull);

      // Malformed JSON should not crash the subscription; it should surface an error.
      chan.serverAddRaw('not-json');
      await tester.pump();

      expect(ws.lastError, isNotNull);
      expect(ws.lastError, contains('Failed to decode WS frame'));

      // Next good frame should be processed and should clear decode errors.
      chan.serverAddJson({
        'v': 2,
        'msg': {
          'type': 'hello',
          'data': {'session_id': 's1', 'server_version': '0.0.0-test'},
        },
      });
      await tester.pump();

      expect(ws.sessionId, 's1');
      expect(ws.serverVersion, '0.0.0-test');
      expect(ws.lastError, isNull);

      await chan.dispose();
      ws.dispose();
      auth.dispose();
    },
  );
}
