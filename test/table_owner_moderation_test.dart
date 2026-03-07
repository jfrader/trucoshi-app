import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:trucoshi_app/platform/platform_caps.dart';
import 'package:trucoshi_app/screens/table_screen.dart';
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
  testWidgets('Table screen lets owners remove players mid-game', (
    tester,
  ) async {
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
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: TableScreen(ws: ws, matchId: 'm1'),
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
            'phase': 'started',
            'owner_seat_idx': 0,
            'players': [
              {'name': 'Fran', 'team': 0, 'ready': true},
              {'name': 'Alex', 'team': 1, 'ready': true},
            ],
          },
          'me': {'seat_idx': 0},
        },
      },
    });
    chan.serverAddJson({
      'v': 2,
      'msg': {
        'type': 'game.snapshot',
        'data': {
          'match_id': 'm1',
          'game': {
            'rounds': [[], []],
            'turn_seat_idx': 0,
          },
          'me': {
            'seat_idx': 0,
            'hand': ['1o', '7c', '5e'],
            'commands': [],
          },
        },
      },
    });
    await tester.pumpAndSettle();

    final removeFinder = find.byKey(const ValueKey('seat-1-remove'));
    expect(removeFinder, findsOneWidget);

    await tester.tap(removeFinder);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Remove').last);
    await tester.pumpAndSettle();

    final sent = chan.sentFramesJson();
    final kicks = sent.where((frame) {
      final msg = frame['msg'];
      if (msg is! Map) return false;
      return msg['type'] == 'match.kick';
    }).toList();

    expect(kicks, isNotEmpty);
    final last = kicks.last;
    final data = ((last['msg'] as Map)['data'] as Map).cast<String, Object?>();
    expect(data['seat_idx'], 1);

    await chan.dispose();
    ws.dispose();
    auth.dispose();
  });
}
