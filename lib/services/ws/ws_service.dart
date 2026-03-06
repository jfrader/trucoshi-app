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
    _lastAuthToken = _auth.accessToken;
    _lastIsGuest = _auth.isGuest;
    _auth.addListener(_onAuthChanged);
  }

  final AuthService _auth;

  String? _lastAuthToken;
  bool _lastIsGuest = false;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _shouldReconnect = true;

  Timer? _pingTimer;

  String? _sessionId;
  String? _serverVersion;
  int? _lastPongRttMs;

  String? get sessionId => _sessionId;
  String? get serverVersion => _serverVersion;
  int? get lastPongRttMs => _lastPongRttMs;

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
      _lastError = 'Missing access token (sign in, or continue as guest)';
      notifyListeners();
      return;
    }

    if (kIsWeb && !isGuest) {
      _lastError =
          'WS auth on web is not supported yet (browsers cannot send Authorization headers). Use guest mode.';
      notifyListeners();
      return;
    }

    _setState(WsConnectionState.connecting);
    _lastError = null;
    _cancelReconnectTimer();
    _cancelPingTimer();

    final uri = AppConfig.wsV2Uri();

    // Ensure previous resources are cleared.
    await _sub?.cancel();
    _sub = null;

    await _channel?.sink.close();
    _channel = null;

    _sessionId = null;
    _serverVersion = null;
    _lastPongRttMs = null;

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
            final text = _eventToText(event);
            if (text == null) {
              _lastError = 'Failed to decode WS frame: unsupported payload type ${event.runtimeType}';
              notifyListeners();
              return;
            }

            final decoded = jsonDecode(text) as Map<String, Object?>;
            final frame = WsOutFrame.fromJson(decoded);

            if (frame.v != 2) {
              _lastError = 'Unsupported WS protocol version: v=${frame.v}';
              notifyListeners();
              return;
            }

            _handleSystemFrame(frame);
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
      _startPingLoop();
    } catch (e) {
      _lastError = 'WS connect failed: $e';
      _setState(WsConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  Future<void> disconnect() async {
    await _disconnectInternal(disableReconnect: true);
  }

  Future<void> _disconnectInternal({required bool disableReconnect}) async {
    if (disableReconnect) {
      _shouldReconnect = false;
    }
    _cancelReconnectTimer();
    _cancelPingTimer();

    _sessionId = null;
    _serverVersion = null;
    _lastPongRttMs = null;

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

  void _startPingLoop() {
    if (_pingTimer != null) return;
    if (_state != WsConnectionState.connected) return;

    void sendPing() {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      send(WsInFrame(msg: WsMsg.ping(clientTimeMs: nowMs)));
    }

    // Immediately ping once on connect for faster liveness/RTT feedback.
    sendPing();

    _pingTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) {
        if (_state != WsConnectionState.connected) return;
        sendPing();
      },
    );
  }

  void _cancelPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _handleSystemFrame(WsOutFrame frame) {
    final type = frame.msg.type;
    final data = frame.msg.data;

    if (type == 'hello' && data != null) {
      final nextSessionId = data['session_id'] as String?;
      final nextServerVersion = data['server_version'] as String?;

      var changed = false;
      if (nextSessionId != null && nextSessionId != _sessionId) {
        _sessionId = nextSessionId;
        changed = true;
      }
      if (nextServerVersion != null && nextServerVersion != _serverVersion) {
        _serverVersion = nextServerVersion;
        changed = true;
      }

      if (changed) notifyListeners();
      return;
    }

    if (type == 'pong' && data != null) {
      final clientTimeMs = data['client_time_ms'];
      if (clientTimeMs is int) {
        final rtt = DateTime.now().millisecondsSinceEpoch - clientTimeMs;
        if (rtt != _lastPongRttMs) {
          _lastPongRttMs = rtt;
          notifyListeners();
        }
      }
      return;
    }
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

    _cancelPingTimer();

    await _channel?.sink.close();
    _channel = null;

    _sessionId = null;
    _serverVersion = null;
    _lastPongRttMs = null;

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

  String? _eventToText(Object? event) {
    if (event == null) return null;
    if (event is String) return event;
    if (event is List<int>) return utf8.decode(event);
    return null;
  }

  void _onAuthChanged() {
    final nextToken = _auth.accessToken;
    final nextIsGuest = _auth.isGuest;

    final credsChanged = nextToken != _lastAuthToken || nextIsGuest != _lastIsGuest;

    _lastAuthToken = nextToken;
    _lastIsGuest = nextIsGuest;

    if (!_auth.isLoggedIn) {
      // If auth is cleared, drop the connection and stop reconnect attempts.
      unawaited(disconnect());
      return;
    }

    if (!credsChanged) return;

    // Switching guest<->auth (or token changes) requires a reconnect to apply
    // headers.
    if (_state == WsConnectionState.connected || _state == WsConnectionState.connecting) {
      unawaited(_restartForCredentialChange());
    } else if (_shouldReconnect) {
      unawaited(connect());
    }
  }

  Future<void> _restartForCredentialChange() async {
    await _disconnectInternal(disableReconnect: false);
    await connect();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    unawaited(disconnect());
    _incoming.close();
    super.dispose();
  }
}
