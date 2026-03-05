import 'package:flutter/foundation.dart';

/// Minimal auth state holder.
///
/// Backend requires `Authorization: Bearer <token>` for `/v2/ws`.
class AuthService extends ChangeNotifier {
  String? _accessToken;

  String? get accessToken => _accessToken;

  bool get isLoggedIn => _accessToken != null && _accessToken!.isNotEmpty;

  void setAccessToken(String? token) {
    final next = token?.trim();
    if (next == _accessToken) return;
    _accessToken = next;
    notifyListeners();
  }

  void logout() => setAccessToken(null);
}
