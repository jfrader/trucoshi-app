import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Minimal auth state holder + HTTP login/register.
///
/// Backend requires `Authorization: Bearer <token>` for `/v2/ws`.
class AuthService extends ChangeNotifier {
  String? _accessToken;
  bool _isGuest = false;

  String? _displayName;

  String? get accessToken => _accessToken;

  bool get isGuest => _isGuest;
  bool get isLoggedIn => _isGuest || (_accessToken != null && _accessToken!.isNotEmpty);

  /// A name to use for match.create/join.
  String get displayName => _displayName ?? (_isGuest ? 'Guest' : 'Player');

  String? _lastError;
  String? get lastError => _lastError;

  void setAccessToken(String? token) {
    final next = token?.trim();
    if (next == _accessToken && !_isGuest) return;
    _accessToken = next;
    _isGuest = false;
    notifyListeners();
  }

  void continueAsGuest() {
    _lastError = null;
    _accessToken = null;
    _isGuest = true;

    // Generate a stable-ish guest name for this session.
    final suffix = DateTime.now().millisecondsSinceEpoch % 1000;
    _displayName = 'Guest$suffix';

    notifyListeners();
  }

  Future<void> register({
    required String email,
    required String password,
    required String name,
  }) async {
    _lastError = null;
    notifyListeners();

    final uri = Uri.parse('${AppConfig.backendBaseUrl}/v1/auth/register');
    final res = await http.post(
      uri,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
        'name': name.trim(),
      }),
    );

    await _handleAuthResponse(res);
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    _lastError = null;
    notifyListeners();

    final uri = Uri.parse('${AppConfig.backendBaseUrl}/v1/auth/login');
    final res = await http.post(
      uri,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
      }),
    );

    await _handleAuthResponse(res);
  }

  Future<void> _handleAuthResponse(http.Response res) async {
    try {
      final json = (jsonDecode(res.body) as Map).cast<String, Object?>();

      if (res.statusCode < 200 || res.statusCode >= 300) {
        _lastError = (json['error'] as String?) ?? 'Login failed';
        notifyListeners();
        return;
      }

      final token = json['access_token'] as String?;
      if (token == null || token.isEmpty) {
        _lastError = 'Missing access_token in response';
        notifyListeners();
        return;
      }

      final user = (json['user'] as Map?)?.cast<String, Object?>();
      final name = user?['name'] as String?;

      _isGuest = false;
      if (name != null && name.trim().isNotEmpty) {
        _displayName = name.trim();
      }
      setAccessToken(token);
    } catch (e) {
      _lastError = 'Failed to parse auth response: $e';
      notifyListeners();
    }
  }

  void logout() {
    _lastError = null;
    _isGuest = false;
    _displayName = null;
    setAccessToken(null);
  }
}
