import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:trucoshi_app/services/auth_service.dart';

void main() {
  test('continueAsGuest sets isGuest and generates a displayName', () {
    final s = AuthService();

    expect(s.isGuest, isFalse);
    s.continueAsGuest();

    expect(s.isGuest, isTrue);
    expect(s.isLoggedIn, isTrue);
    expect(s.accessToken, isNull);
    expect(s.displayName, isNotEmpty);
    expect(s.displayName.startsWith('Guest'), isTrue);
  });

  test('continueAsGuest uses provided displayName', () {
    final s = AuthService();
    s.continueAsGuest(displayName: ' Fran ');

    expect(s.isGuest, isTrue);
    expect(s.displayName, 'Fran');
  });

  test('useToken sets token and clears guest mode', () {
    final s = AuthService();
    s.continueAsGuest();
    expect(s.isGuest, isTrue);

    s.useToken('abc', displayName: 'Player1');
    expect(s.isGuest, isFalse);
    expect(s.accessToken, 'abc');
    expect(s.isLoggedIn, isTrue);
    expect(s.displayName, 'Player1');
  });

  test('login success stores access_token and user name', () async {
    final client = MockClient((req) async {
      return http.Response(
        jsonEncode({
          'access_token': 'tok',
          'user': {'name': 'Fran'},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final s = AuthService(httpClient: client);
    await s.login(email: 'a@b.com', password: 'pw');

    expect(s.lastError, isNull);
    expect(s.accessToken, 'tok');
    expect(s.isGuest, isFalse);
    expect(s.displayName, 'Fran');
  });

  test('login failure sets lastError', () async {
    final client = MockClient((req) async {
      return http.Response(
        jsonEncode({'error': 'nope'}),
        401,
        headers: {'content-type': 'application/json'},
      );
    });

    final s = AuthService(httpClient: client);
    await s.login(email: 'a@b.com', password: 'pw');

    expect(s.accessToken, isNull);
    expect(s.isLoggedIn, isFalse);
    expect(s.lastError, 'nope');
  });

  test('login malformed response sets lastError', () async {
    final client = MockClient((req) async {
      return http.Response('not-json', 200);
    });

    final s = AuthService(httpClient: client);
    await s.login(email: 'a@b.com', password: 'pw');

    expect(s.accessToken, isNull);
    expect(s.lastError, contains('Failed to parse auth response'));
  });

  test('forgotPassword hits endpoint and returns null on success', () async {
    late http.Request captured;
    final client = MockClient((req) async {
      captured = req;
      return http.Response('', 204);
    });

    final s = AuthService(httpClient: client);
    final err = await s.forgotPassword('player@example.com');

    expect(err, isNull);
    expect(captured.url.path, contains('/v1/auth/forgot-password'));
    expect(captured.body, contains('player@example.com'));
  });

  test('resetPassword forwards backend error message', () async {
    final client = MockClient((req) async {
      return http.Response(jsonEncode({'error': 'invalid token'}), 400);
    });

    final s = AuthService(httpClient: client);
    final err = await s.resetPassword(token: 'abc', password: 'password1');

    expect(err, 'invalid token');
  });

  test('verifyEmail returns null on success', () async {
    late http.Request captured;
    final client = MockClient((req) async {
      captured = req;
      return http.Response('', 204);
    });

    final s = AuthService(httpClient: client);
    final err = await s.verifyEmail('token-123');

    expect(err, isNull);
    expect(captured.url.path, contains('/v1/auth/verify-email'));
    expect(captured.body, contains('token-123'));
  });

  test('sendVerificationEmail requires login', () async {
    final s = AuthService();
    final err = await s.sendVerificationEmail();
    expect(err, contains('iniciar sesión'));
  });
}
