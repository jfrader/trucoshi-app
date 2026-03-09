import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:trucoshi_app/platform/platform_caps.dart';
import 'package:trucoshi_app/screens/lobby_screen.dart';
import 'package:trucoshi_app/services/auth_service.dart';
import 'package:trucoshi_app/services/ws/ws_service.dart';

class _FakeHttpResponse {
  const _FakeHttpResponse({
    required this.body,
    this.statusCode = 200,
    this.headers = const {'content-type': 'application/json'},
  });

  final String body;
  final int statusCode;
  final Map<String, String> headers;
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient({List<_FakeHttpResponse>? seed})
    : _responses = ListQueue<_FakeHttpResponse>.from(seed ?? const []);

  final ListQueue<_FakeHttpResponse> _responses;
  final recordedRequests = <http.BaseRequest>[];
  bool closed = false;

  void enqueue(_FakeHttpResponse response) {
    _responses.addLast(response);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    recordedRequests.add(request);
    final next = _responses.isEmpty
        ? const _FakeHttpResponse(body: '{}')
        : _responses.removeFirst();
    final stream = Stream<List<int>>.fromIterable([utf8.encode(next.body)]);
    return http.StreamedResponse(
      stream,
      next.statusCode,
      headers: next.headers,
    );
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

class _FakeWebSocketSink extends DelegatingStreamSink<Object?>
    implements WebSocketSink {
  _FakeWebSocketSink(this._controller) : super(_controller.sink);

  final StreamController<Object?> _controller;
  final added = <Object?>[];

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

    for (final entry in _sink.added) {
      if (entry is! String) continue;
      out.add((jsonDecode(entry) as Map).cast<String, Object?>());
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
  testWidgets('Signed-in lobby surfaces resume list with online estimate', (
    tester,
  ) async {
    final auth = AuthService();
    auth.useToken('test-token', displayName: 'Fran');

    final httpClient = _FakeHttpClient(
      seed: [
        _FakeHttpResponse(
          body: jsonEncode({
            'matches': [
              {
                'match': {
                  'id': 'resume-123',
                  'phase': 'playing',
                  'players': [
                    {'name': 'Fran'},
                    {'name': 'Mia'},
                  ],
                  'options': {'max_players': 4},
                  'spectator_count': 2,
                },
                'me': {'team': 1, 'ready': false, 'disconnected_at_ms': 1234},
              },
            ],
          }),
        ),
      ],
    );

    final chan = _FakeWebSocketChannel();
    final caps = const PlatformCaps(supportsWsAuthHeaders: true);

    final ws = WsService(
      auth: auth,
      caps: caps,
      channelFactory: (uri, {headers}) => chan,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.deepOrange,
        ),
        home: LobbyScreen(
          auth: auth,
          ws: ws,
          caps: caps,
          httpClientBuilder: () => httpClient,
        ),
      ),
    );
    await tester.pump();

    chan.serverAddJson({
      'v': 2,
      'msg': {
        'type': 'lobby.snapshot',
        'data': {
          'matches': [
            {
              'id': 'm1',
              'phase': 'lobby',
              'players': [
                {'name': 'Fran'},
                {'name': 'Lia'},
              ],
              'options': {'max_players': 4},
              'spectator_count': 1,
            },
          ],
          'stats': {'online_players': 42},
        },
      },
    });

    chan.serverAddJson({
      'v': 2,
      'msg': {
        'type': 'me.active_matches',
        'data': {
          'matches': [
            {
              'match': {
                'id': 'resume-123',
                'phase': 'playing',
                'players': [
                  {'name': 'Fran'},
                  {'name': 'Mia'},
                ],
                'options': {'max_players': 4},
                'spectator_count': 2,
              },
              'me': {'team': 1, 'ready': false, 'disconnected_at_ms': 1234},
            },
          ],
        },
      },
    });

    await tester.pumpAndSettle();

    expect(find.text('Resume matches'), findsOneWidget);
    expect(find.text('Match resume-123'), findsOneWidget);
    expect(find.text('Online players: 42'), findsOneWidget);

    expect(httpClient.recordedRequests, isNotEmpty);
    final req = httpClient.recordedRequests.first;
    expect(req.url.path, '/v1/matches/active');
    expect(req.headers['authorization'], 'Bearer test-token');

    httpClient.enqueue(const _FakeHttpResponse(body: '{"matches":[]}'));

    await tester.tap(find.byTooltip('Refresh resume list'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final sent = chan.sentFramesJson();
    int countMsg(String type) {
      return sent.where((frame) {
        final msg = frame['msg'];
        return msg is Map && msg['type'] == type;
      }).length;
    }

    expect(countMsg('lobby.snapshot.get'), 2);
    expect(countMsg('me.active_matches.get'), 2);

    await tester.pumpWidget(const SizedBox());

    await chan.dispose();
    ws.dispose();
    auth.dispose();
    httpClient.close();
  });

  testWidgets('Lobby swaps from estimate to stats when lobby.stats arrives', (
    tester,
  ) async {
    final auth = AuthService();
    auth.useToken('test-token', displayName: 'Fran');

    final httpClient = _FakeHttpClient(
      seed: [
        _FakeHttpResponse(
          body: jsonEncode({
            'matches': [
              {
                'match': {
                  'id': 'resume-123',
                  'phase': 'playing',
                  'players': [
                    {'name': 'Fran'},
                    {'name': 'Mia'},
                  ],
                  'options': {'max_players': 4},
                  'spectator_count': 2,
                },
                'me': {'team': 1, 'ready': false, 'disconnected_at_ms': 1234},
              },
            ],
          }),
        ),
      ],
    );

    final chan = _FakeWebSocketChannel();
    final caps = const PlatformCaps(supportsWsAuthHeaders: true);

    final ws = WsService(
      auth: auth,
      caps: caps,
      channelFactory: (uri, {headers}) => chan,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.deepOrange,
        ),
        home: LobbyScreen(
          auth: auth,
          ws: ws,
          caps: caps,
          httpClientBuilder: () => httpClient,
        ),
      ),
    );
    await tester.pump();

    chan.serverAddJson({
      'v': 2,
      'msg': {
        'type': 'lobby.snapshot',
        'data': {
          'matches': [
            {
              'id': 'm1',
              'phase': 'lobby',
              'players': [
                {'name': 'Fran'},
                {'name': 'Lia'},
              ],
              'options': {'max_players': 4},
              'spectator_count': 1,
            },
          ],
          'stats': null,
        },
      },
    });

    chan.serverAddJson({
      'v': 2,
      'msg': {
        'type': 'me.active_matches',
        'data': {
          'matches': [
            {
              'match': {
                'id': 'resume-123',
                'phase': 'playing',
                'players': [
                  {'name': 'Fran'},
                  {'name': 'Mia'},
                ],
                'options': {'max_players': 4},
                'spectator_count': 2,
              },
              'me': {'team': 1, 'ready': false, 'disconnected_at_ms': 1234},
            },
          ],
        },
      },
    });

    await tester.pumpAndSettle();

    expect(find.text('Online players (estimate): 3'), findsOneWidget);

    chan.serverAddJson({
      'v': 2,
      'msg': {
        'type': 'lobby.stats',
        'data': {'online_players': 9},
      },
    });

    await tester.pumpAndSettle();

    expect(find.text('Online players: 9'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());

    await chan.dispose();
    ws.dispose();
    auth.dispose();
    httpClient.close();
  });

  testWidgets('Guest lobby hides resume UI', (tester) async {
    final auth = AuthService();
    auth.continueAsGuest(displayName: 'Guest');

    final httpClient = _FakeHttpClient();
    final chan = _FakeWebSocketChannel();
    final caps = const PlatformCaps(supportsWsAuthHeaders: true);

    final ws = WsService(
      auth: auth,
      caps: caps,
      channelFactory: (uri, {headers}) => chan,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
        home: LobbyScreen(
          auth: auth,
          ws: ws,
          caps: caps,
          httpClientBuilder: () => httpClient,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Resume matches'), findsNothing);

    await tester.pumpWidget(const SizedBox());

    await chan.dispose();
    ws.dispose();
    auth.dispose();
    httpClient.close();
  });
}
