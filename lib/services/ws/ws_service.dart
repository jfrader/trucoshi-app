import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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

  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _shouldReconnect = true;

  int _reqSeq = 0;

  WsConnectionState _state = WsConnectionState.disconnected;
  WsConnectionState get state => _state;

  final _incoming = StreamController<WsOutFrame>.broadcast();
  Stream<WsOutFrame> get incoming => _incoming.stream;

  String? _lastError;
  String? get lastError => _lastError;

  Future<void> connect() async {
    _shouldReconnect = true;

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
    _cancelReconnectTimer();

    final uri = AppConfig.wsV2Uri();

    // Ensure previous resources are cleared.
    await _sub?.cancel();
    _sub = null;

    await _channel?.sink.close();
    _channel = null;

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
          _onSocketClosed();
        },
        onError: (Object e) {
          _lastError = 'WS error: $e';
          _onSocketClosed();
        },
      );

      _reconnectAttempts = 0;
      _setState(WsConnectionState.connected);
    } catch (e) {
      _lastError = 'WS connect failed: $e';
      _setState(WsConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _cancelReconnectTimer();

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

  Future<WsOutFrame> request(
    WsMsg msg, {
    String? id,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_state != WsConnectionState.connected) {
      await connect();
    }

    if (_state != WsConnectionState.connected) {
      throw StateError(_lastError ?? 'WS not connected');
    }

    final rid = id ?? _nextRequestId();

    final future = incoming
        .where((f) => f.id == rid)
        .first
        .timeout(timeout);

    send(WsInFrame(id: rid, msg: msg));

    return future;
  }

  void _setState(WsConnectionState s) {
    if (s == _state) return;
    _state = s;
    notifyListeners();
  }

  void _onSocketClosed() {
    // When the underlying socket closes unexpectedly, clean up and attempt a
    // reconnect (unless explicitly disabled).
    unawaited(_cleanupClosedSocket());
  }

  Future<void> _cleanupClosedSocket() async {
    await _sub?.cancel();
    _sub = null;

    await _channel?.sink.close();
    _channel = null;

    _setState(WsConnectionState.disconnected);

    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    if (!_auth.isLoggedIn) return;
    if (_reconnectTimer != null) return;
    if (_state == WsConnectionState.connecting) return;

    const delays = [1, 2, 4, 8, 15, 30];
    final idx = math.min(_reconnectAttempts, delays.length - 1);
    final delay = Duration(seconds: delays[idx]);
    _reconnectAttempts++;

    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      unawaited(connect());
    });

    notifyListeners();
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  String _nextRequestId() {
    _reqSeq++;
    return 'r${DateTime.now().microsecondsSinceEpoch}-$_reqSeq';
  }

  void _onAuthChanged() {
    if (!_auth.isLoggedIn) {
      // If token is cleared, drop the connection and stop reconnect attempts.
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
