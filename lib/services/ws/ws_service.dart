import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../config/app_config.dart';
import '../auth_service.dart';
import 'v2_types.dart';
import 'ws_connector.dart';

enum WsConnectionState {
  disconnected,
  connecting,
  connected,
}

class WsService extends ChangeNotifier {
  WsService({required AuthService auth}) : _auth = auth {
    _auth.addListener(_onAuthChanged);
  }

  final AuthService _auth;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  WsConnectionState _state = WsConnectionState.disconnected;
  WsConnectionState get state => _state;

  final _incoming = StreamController<WsOutFrame>.broadcast();
  Stream<WsOutFrame> get incoming => _incoming.stream;

  String? _lastError;
  String? get lastError => _lastError;

  Future<void> connect() async {
    if (_state == WsConnectionState.connected ||
        _state == WsConnectionState.connecting) {
      return;
    }

    final token = _auth.accessToken;
    final isGuest = _auth.isGuest;

    if (!isGuest && (token == null || token.isEmpty)) {
      _lastError = 'Missing access token';
      notifyListeners();
      return;
    }

    _setState(WsConnectionState.connecting);
    _lastError = null;

    final uri = AppConfig.wsV2Uri();

    try {
      final headers = isGuest
          ? null
          : {
              'Authorization': 'Bearer $token',
            };

      _channel = connectWs(uri, headers: headers);

      _sub = _channel!.stream.listen(
        (event) {
          try {
            final decoded = jsonDecode(event as String) as Map<String, Object?>;
            final frame = WsOutFrame.fromJson(decoded);
            _incoming.add(frame);
          } catch (e) {
            _lastError = 'Failed to decode WS frame: $e';
            notifyListeners();
          }
        },
        onDone: () {
          _setState(WsConnectionState.disconnected);
        },
        onError: (Object e) {
          _lastError = 'WS error: $e';
          _setState(WsConnectionState.disconnected);
        },
      );

      _setState(WsConnectionState.connected);
    } catch (e) {
      _lastError = 'WS connect failed: $e';
      _setState(WsConnectionState.disconnected);
    }
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;

    await _channel?.sink.close();
    _channel = null;

    _setState(WsConnectionState.disconnected);
  }

  void send(WsInFrame frame) {
    final chan = _channel;
    if (chan == null || _state != WsConnectionState.connected) return;
    chan.sink.add(frame.encode());
  }

  void _setState(WsConnectionState s) {
    if (s == _state) return;
    _state = s;
    notifyListeners();
  }

  void _onAuthChanged() {
    if (!_auth.isLoggedIn) {
      // If token is cleared, drop the connection.
      unawaited(disconnect());
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    unawaited(disconnect());
    _incoming.close();
    super.dispose();
  }
}
