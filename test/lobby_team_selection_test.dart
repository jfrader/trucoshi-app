import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:trucoshi_app/platform/platform_caps.dart';
import 'package:trucoshi_app/screens/lobby_screen.dart';
import 'package:trucoshi_app/services/auth_service.dart';
import 'package:trucoshi_app/services/ws/ws_service.dart';

class _FakeWebSocketSink extends DelegatingStreamSink<Object?>
    implements WebSocketSink {
  _FakeWebSocketSink(this._controller) : super(_controller.sink);

  final StreamController<Object?> _controller;
  final List<Object?> added = [];

  int? _closeCode;
  String? _closeReason;

  int? get closeCode => _closeCode;
  String? get closeReason => _closeReason;

  @override
  void add(Object? data) {
    added.add(data);
    super.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    // Not needed for these tests.
    super.addError(error, stackTrace);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _closeCode = closeCode;
    _closeReason = closeReason;
    await _controller.close();
  }
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

  void serverAddJson(Map<String, Object?> frame) {
    _server.add(jsonEncode(frame));
  }

  List<Map<String, Object?>> sentFramesJson() {
    final out = <Map<String, Object?>>[];

    for (final e in _sink.added) {
      if (e is! String) continue;
      out.add((jsonDecode(e) as Map).cast<String, Object?>());
    }

    return out;
  }

  Future<void> dispose() async {
    await _server.close();
    await _clientController.close();
    await sink.close();
  }
}

void main() {
  testWidgets(
    'Lobby prompts for team when joining a 4+ player match and includes team in match.join',
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

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.red),
          home: LobbyScreen(auth: auth, ws: ws, caps: caps),
        ),
      );
      await tester.pumpAndSettle();

      chan.serverAddJson({
        'v': 2,
        'msg': {
          'type': 'lobby.snapshot',
          'data': {
            'matches': [
              {
                'id': 'm1',
                'phase': 'lobby',
                'players': [],
                'options': {
                  'max_players': 4,
                  'flor': true,
                  'match_points': 9,
                  'turn_time_ms': 30000,
                },
              },
            ],
          },
        },
      });
      await tester.pumpAndSettle();

      expect(find.text('Match m1'), findsOneWidget);

      await tester.tap(find.text('Match m1'));
      await tester.pumpAndSettle();

      expect(find.text('Join match'), findsOneWidget);

      await tester.tap(find.text('Team 1'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();

      final sent = chan.sentFramesJson();
      final joinFrames = sent.where((f) {
        final msg = f['msg'];
        if (msg is! Map) return false;
        return msg['type'] == 'match.join';
      }).toList();

      expect(joinFrames, isNotEmpty);

      final last = joinFrames.last;
      final msg = (last['msg'] as Map).cast<String, Object?>();
      final data = (msg['data'] as Map).cast<String, Object?>();

      expect(data['match_id'], 'm1');
      expect(data['name'], 'Fran');
      expect(data['team'], 1);

      await chan.dispose();
      ws.dispose();
      auth.dispose();
    },
  );

  testWidgets(
    'Create match dialog can set team and includes it in match.create',
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

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.red),
          home: LobbyScreen(auth: auth, ws: ws, caps: caps),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create match'));
      await tester.pumpAndSettle();

      expect(find.text('Team (optional):'), findsOneWidget);

      await tester.tap(find.text('Team 0'));
      await tester.pumpAndSettle();

      // Switch max players to 4 so it matches the typical use for team picking.
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4 (2v2)').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      final sent = chan.sentFramesJson();
      final createFrames = sent.where((f) {
        final msg = f['msg'];
        if (msg is! Map) return false;
        return msg['type'] == 'match.create';
      }).toList();

      expect(createFrames, isNotEmpty);

      final last = createFrames.last;
      final msg = (last['msg'] as Map).cast<String, Object?>();
      final data = (msg['data'] as Map).cast<String, Object?>();

      expect(data['name'], 'Fran');
      expect(data['team'], 0);

      final opts = (data['options'] as Map).cast<String, Object?>();
      expect(opts['max_players'], 4);

      await chan.dispose();
      ws.dispose();
      auth.dispose();
    },
  );
}
