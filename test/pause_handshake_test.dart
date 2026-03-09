import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:trucoshi_app/platform/platform_caps.dart';
import 'package:trucoshi_app/screens/match_screen.dart';
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
  const caps = PlatformCaps(supportsWsAuthHeaders: true);

  testWidgets('Match screen pause banner wires votes for awaiting seats', (
    tester,
  ) async {
    final auth = AuthService();
    auth.continueAsGuest(displayName: 'Fran');

    final chan = _FakeWebSocketChannel();
    final ws = WsService(
      auth: auth,
      caps: caps,
      channelFactory: (uri, {headers}) => chan,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: MatchScreen(ws: ws, matchId: 'match-1'),
      ),
    );
    await tester.pumpAndSettle();

    final expiresAt = DateTime.now().millisecondsSinceEpoch + 60000;

    chan.serverAddJson({
      'v': 2,
      'msg': {
        'type': 'match.snapshot',
        'data': {
          'match': {
            'id': 'match-1',
            'name': 'Friday',
            'phase': 'started',
            'owner_seat_idx': 0,
            'players': [
              {'name': 'Owner', 'team': 0, 'ready': true},
              {'name': 'A', 'team': 1, 'ready': true},
              {'name': 'B', 'team': 0, 'ready': true},
              {'name': 'Fran', 'team': 1, 'ready': true},
            ],
            'pause_request': {
              'requested_by_seat_idx': 0,
              'requested_by_team': 0,
              'awaiting_team': 1,
              'expires_at_ms': expiresAt,
              'accepted_seat_idxs': [1],
            },
          },
          'me': {'seat_idx': 3},
        },
      },
    });
    await tester.pumpAndSettle();

    expect(find.textContaining('Pause requested by'), findsOneWidget);
    expect(find.textContaining('Request expires in'), findsOneWidget);

    final accept = find.widgetWithText(FilledButton, 'Accept pause');
    expect(accept, findsOneWidget);
    await tester.tap(accept);
    await tester.pump();

    final sentAfter = chan.sentFramesJson();
    final hasAcceptVote = sentAfter.any((frame) {
      final msg = frame['msg'];
      if (msg is! Map) return false;
      if (msg['type'] != 'match.pause.vote') return false;
      final data = msg['data'];
      return data is Map && data['accept'] == true;
    });
    expect(hasAcceptVote, isTrue);

    await chan.dispose();
    ws.dispose();
    auth.dispose();
  });

  testWidgets('Match screen owner can pause and resume matches', (
    tester,
  ) async {
    final auth = AuthService();
    auth.continueAsGuest(displayName: 'Owner');

    final chan = _FakeWebSocketChannel();
    final ws = WsService(
      auth: auth,
      caps: caps,
      channelFactory: (uri, {headers}) => chan,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: MatchScreen(ws: ws, matchId: 'm2'),
      ),
    );
    await tester.pumpAndSettle();

    void pushMatchFrame(String phase, {Map<String, Object?>? extra}) {
      final match = <String, Object?>{
        'id': 'm2',
        'name': 'Friday',
        'phase': phase,
        'owner_seat_idx': 0,
        'players': [
          {'name': 'Owner', 'team': 0, 'ready': true},
          {'name': 'Alex', 'team': 1, 'ready': true},
        ],
      };
      if (extra != null) {
        match.addAll(extra);
      }
      chan.serverAddJson({
        'v': 2,
        'msg': {
          'type': 'match.snapshot',
          'data': {
            'match': match,
            'me': {'seat_idx': 0},
          },
        },
      });
    }

    pushMatchFrame('started');
    await tester.pumpAndSettle();

    final pauseButton = find.widgetWithText(FilledButton, 'Pause match');
    await tester.scrollUntilVisible(
      pauseButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(pauseButton, findsOneWidget);
    await tester.tap(pauseButton);
    await tester.pump();

    final pauseSent = chan.sentFramesJson().last;
    expect((pauseSent['msg'] as Map)['type'], 'match.pause');
    final pauseId = pauseSent['id'];

    chan.serverAddJson({
      'v': 2,
      'id': pauseId,
      'msg': {'type': 'ok', 'data': const {}},
    });
    await tester.pump();

    pushMatchFrame('paused');
    await tester.pumpAndSettle();

    final resumeButton = find.widgetWithText(FilledButton, 'Resume match');
    await tester.scrollUntilVisible(
      resumeButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(resumeButton, findsOneWidget);
    await tester.tap(resumeButton);
    await tester.pump();

    final resumeSent = chan.sentFramesJson().last;
    expect((resumeSent['msg'] as Map)['type'], 'match.resume');

    await chan.dispose();
    ws.dispose();
    auth.dispose();
  });

  testWidgets('Table screen shows pause banners and vote buttons', (
    tester,
  ) async {
    final auth = AuthService();
    auth.continueAsGuest(displayName: 'Fran');

    final chan = _FakeWebSocketChannel();
    final ws = WsService(
      auth: auth,
      caps: caps,
      channelFactory: (uri, {headers}) => chan,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: TableScreen(ws: ws, matchId: 'table-1'),
      ),
    );
    await tester.pumpAndSettle();

    final expiresAt = DateTime.now().millisecondsSinceEpoch + 45000;

    chan.serverAddJson({
      'v': 2,
      'msg': {
        'type': 'match.snapshot',
        'data': {
          'match': {
            'id': 'table-1',
            'phase': 'started',
            'owner_seat_idx': 0,
            'players': [
              {'name': 'Owner', 'team': 0, 'ready': true},
              {'name': 'You', 'team': 1, 'ready': true},
              {'name': 'B', 'team': 0, 'ready': true},
              {'name': 'C', 'team': 1, 'ready': true},
            ],
            'pause_request': {
              'requested_by_seat_idx': 0,
              'awaiting_team': 1,
              'expires_at_ms': expiresAt,
              'accepted_seat_idxs': [1],
            },
            'pending_unpause': {'resume_at_ms': expiresAt + 15000},
          },
          'me': {'seat_idx': 3},
        },
      },
    });
    chan.serverAddJson({
      'v': 2,
      'msg': {
        'type': 'game.snapshot',
        'data': {
          'match_id': 'table-1',
          'game': {
            'rounds': [[], []],
            'turn_seat_idx': 3,
          },
          'me': {
            'seat_idx': 3,
            'hand': ['1o', '7c', '5e'],
            'commands': [],
          },
        },
      },
    });
    await tester.pumpAndSettle();

    expect(find.textContaining('Pause requested by'), findsOneWidget);
    expect(find.textContaining('Resuming in'), findsOneWidget);

    final accept = find.widgetWithText(FilledButton, 'Accept pause');
    expect(accept, findsOneWidget);
    await tester.tap(accept);
    await tester.pump();

    final sent = chan.sentFramesJson();
    expect(sent.last['msg'] is Map, isTrue);
    final msg = (sent.last['msg'] as Map).cast<String, Object?>();
    expect(msg['type'], 'match.pause.vote');
    expect((msg['data'] as Map)['accept'], true);

    await chan.dispose();
    ws.dispose();
    auth.dispose();
  });

  testWidgets('Table screen owner can pause and resume', (tester) async {
    final auth = AuthService();
    auth.continueAsGuest(displayName: 'Owner');

    final chan = _FakeWebSocketChannel();
    final ws = WsService(
      auth: auth,
      caps: caps,
      channelFactory: (uri, {headers}) => chan,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: TableScreen(ws: ws, matchId: 'table-2'),
      ),
    );
    await tester.pumpAndSettle();

    void pushMatch({required String phase, Map<String, Object?>? extra}) {
      final match = <String, Object?>{
        'id': 'table-2',
        'phase': phase,
        'owner_seat_idx': 0,
        'players': [
          {'name': 'Owner', 'team': 0, 'ready': true},
          {'name': 'Alex', 'team': 1, 'ready': true},
        ],
      };
      if (extra != null) {
        match.addAll(extra);
      }
      chan.serverAddJson({
        'v': 2,
        'msg': {
          'type': 'match.snapshot',
          'data': {
            'match': match,
            'me': {'seat_idx': 0},
          },
        },
      });
    }

    chan.serverAddJson({
      'v': 2,
      'msg': {
        'type': 'game.snapshot',
        'data': {
          'match_id': 'table-2',
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

    pushMatch(phase: 'started');
    await tester.pumpAndSettle();

    final pauseButton = find.widgetWithText(FilledButton, 'Pause match');
    expect(pauseButton, findsOneWidget);
    await tester.tap(pauseButton);
    await tester.pump();
    final pauseMsg = (chan.sentFramesJson().last['msg'] as Map);
    expect(pauseMsg['type'], 'match.pause');
    final pauseId = chan.sentFramesJson().last['id'];

    chan.serverAddJson({
      'v': 2,
      'id': pauseId,
      'msg': {'type': 'ok', 'data': const {}},
    });
    await tester.pump();

    pushMatch(phase: 'paused');
    await tester.pumpAndSettle();

    final resumeButton = find.widgetWithText(FilledButton, 'Resume match');
    expect(resumeButton, findsOneWidget);
    await tester.tap(resumeButton);
    await tester.pump();

    final resumeMsg = (chan.sentFramesJson().last['msg'] as Map);
    expect(resumeMsg['type'], 'match.resume');

    await chan.dispose();
    ws.dispose();
    auth.dispose();
  });
}
