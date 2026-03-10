import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Minimal auth state holder + HTTP login/register.
///
/// WS v2 supports both:
/// - **Guest mode**: connect to `/v2/ws` with no auth header.
/// - **Authenticated mode**: `Authorization: Bearer <token>`.
class AuthService extends ChangeNotifier {
  AuthService({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  String? _accessToken;
  bool _isGuest = false;

  String? _displayName;

  String? get accessToken => _accessToken;

  bool get isGuest => _isGuest;
  bool get isLoggedIn =>
      _isGuest || (_accessToken != null && _accessToken!.isNotEmpty);

  /// A name to use for match.create/join.
  String get displayName => _displayName ?? (_isGuest ? 'Guest' : 'Player');

  String? _lastError;
  String? get lastError => _lastError;

  void setDisplayName(String? name) {
    final next = name?.trim();
    if (next == null || next.isEmpty) return;
    if (next == _displayName) return;
    _displayName = next;
    notifyListeners();
  }

  void setAccessToken(String? token) {
    final next = token?.trim();
    if (next == _accessToken && !_isGuest) return;
    _accessToken = next;
    _isGuest = false;
    notifyListeners();
  }

  /// Dev-friendly: treat a pasted token as a successful login.
  void useToken(String token, {String? displayName}) {
    _lastError = null;
    if (displayName != null && displayName.trim().isNotEmpty) {
      _displayName = displayName.trim();
    }
    setAccessToken(token);
  }

  void continueAsGuest({String? displayName}) {
    _lastError = null;
    _accessToken = null;
    _isGuest = true;

    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) {
      _displayName = name;
    } else if (_displayName == null || _displayName!.trim().isEmpty) {
      // Generate a stable-ish guest name for this session.
      final suffix = DateTime.now().millisecondsSinceEpoch % 1000;
      _displayName = 'Guest$suffix';
    }

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
    final res = await _http.post(
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

  Future<void> login({required String email, required String password}) async {
    _lastError = null;
    notifyListeners();

    final uri = Uri.parse('${AppConfig.backendBaseUrl}/v1/auth/login');
    final res = await _http.post(
      uri,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'email': email.trim(), 'password': password}),
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

  Future<String?> sendVerificationEmail() async {
    final token = _accessToken;
    if (token == null || token.isEmpty) {
      return 'Necesitás iniciar sesión para reenviar el email de verificación.';
    }

    final uri = Uri.parse(
      '${AppConfig.backendBaseUrl}/v1/auth/send-verification-email',
    );

    try {
      final res = await _http.post(
        uri,
        headers: {'authorization': 'Bearer $token'},
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return null;
      }

      return _errorFromResponse(
        res,
        'No pudimos enviar el email de verificación',
      );
    } catch (e) {
      return 'No pudimos enviar el email de verificación: $e';
    }
  }

  Future<String?> verifyEmail(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      return 'El token de verificación es obligatorio.';
    }

    final uri = Uri.parse('${AppConfig.backendBaseUrl}/v1/auth/verify-email');

    try {
      final res = await _http.post(
        uri,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'token': trimmed}),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return null;
      }

      return _errorFromResponse(res, 'El token no es válido o expiró');
    } catch (e) {
      return 'No pudimos verificar tu email: $e';
    }
  }

  Future<String?> forgotPassword(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      return 'Necesitamos tu email para enviar el link de restablecimiento.';
    }

    final uri = Uri.parse(
      '${AppConfig.backendBaseUrl}/v1/auth/forgot-password',
    );

    try {
      final res = await _http.post(
        uri,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'email': trimmed}),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return null;
      }

      return _errorFromResponse(
        res,
        'No pudimos enviar el email de restablecimiento',
      );
    } catch (e) {
      return 'No pudimos enviar el email de restablecimiento: $e';
    }
  }

  Future<String?> resetPassword({
    required String token,
    required String password,
  }) async {
    final trimmedToken = token.trim();
    if (trimmedToken.isEmpty) {
      return 'El token del email es obligatorio.';
    }

    final uri = Uri.parse('${AppConfig.backendBaseUrl}/v1/auth/reset-password');

    try {
      final res = await _http.post(
        uri,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'token': trimmedToken, 'password': password}),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return null;
      }

      return _errorFromResponse(res, 'No pudimos actualizar tu contraseña');
    } catch (e) {
      return 'No pudimos actualizar tu contraseña: $e';
    }
  }

  void logout() {
    _lastError = null;
    _isGuest = false;
    _displayName = null;
    setAccessToken(null);
  }

  String _errorFromResponse(http.Response res, String fallback) {
    if (res.body.isNotEmpty) {
      try {
        final raw = jsonDecode(res.body);
        if (raw is Map) {
          final msg = raw['error'];
          if (msg is String && msg.trim().isNotEmpty) {
            return msg.trim();
          }
        }
      } catch (_) {
        final snippet = res.body.length > 120
            ? '${res.body.substring(0, 117)}...'
            : res.body;
        if (snippet.trim().isNotEmpty) {
          return snippet.trim();
        }
      }
    }

    return '$fallback (status ${res.statusCode})';
  }
}
