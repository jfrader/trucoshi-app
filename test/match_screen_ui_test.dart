import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:trucoshi_app/screens/match_screen.dart';
import 'package:trucoshi_app/platform/platform_caps.dart';
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

  Future<void> dispose() async {
    await _server.close();
    await _clientController.close();
    await sink.close();
  }
}

void main() {
  testWidgets('Match screen shows summary, options, and players', (tester) async {
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
        home: MatchScreen(ws: ws, matchId: 'm1'),
      ),
    );
    await tester.pumpAndSettle();

    chan.serverAddJson({
      'v': 2,
      'msg': {
        'type': 'match.snapshot',
        'data': {
          'match': {
            'id': 'm1',
            'name': 'Friday Match',
            'phase': 'lobby',
            'owner_seat_idx': 0,
            'players': [
              {'name': 'Fran', 'team': 0, 'ready': true},
              {'name': 'Alex', 'team': 1, 'ready': false},
            ],
            'max_players': 2,
            'match_points': 9,
            'turn_time_ms': 30000,
            'flor': true,
            'team_points': [3, 5],
            'options': {
              'max_players': 2,
              'match_points': 9,
              'turn_time_ms': 30000,
              'flor': true,
            },
          },
          'me': {'seat_idx': 0},
        },
      },
    });
    await tester.pumpAndSettle();

    expect(find.text('Friday Match'), findsOneWidget);
    expect(find.textContaining('players: 2/2'), findsOneWidget);
    expect(find.textContaining('ready: 1/2'), findsOneWidget);

    expect(find.text('Fran'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.textContaining('Seat 0 • Team 0'), findsOneWidget);
    expect(find.textContaining('Seat 1 • Team 1'), findsOneWidget);

    await chan.dispose();
    ws.dispose();
    auth.dispose();
  });
}
