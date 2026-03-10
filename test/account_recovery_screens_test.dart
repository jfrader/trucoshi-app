import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:trucoshi_app/screens/forgot_password_screen.dart';
import 'package:trucoshi_app/screens/reset_password_screen.dart';
import 'package:trucoshi_app/screens/verify_email_screen.dart';
import 'package:trucoshi_app/services/auth_service.dart';

void main() {
  testWidgets('ForgotPasswordScreen surfaces success banner', (tester) async {
    var called = false;
    final client = MockClient((req) async {
      called = true;
      expect(req.url.path, contains('/v1/auth/forgot-password'));
      return http.Response('', 204);
    });

    final auth = AuthService(httpClient: client);
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      MaterialApp(home: ForgotPasswordScreen(auth: auth)),
    );

    await tester.enterText(find.byType(TextField), 'player@example.com');
    await tester.tap(find.text('Enviar email de restablecimiento'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(
      find.textContaining('Te enviamos un email con instrucciones'),
      findsOneWidget,
    );
  });

  testWidgets(
    'ResetPasswordScreen validates confirmations before calling API',
    (tester) async {
      var called = false;
      final client = MockClient((req) async {
        called = true;
        return http.Response('', 204);
      });

      final auth = AuthService(httpClient: client);
      addTearDown(auth.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ResetPasswordScreen(auth: auth, token: 'tok'),
        ),
      );

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'password123');
      await tester.enterText(fields.at(1), 'different');
      await tester.tap(find.text('Restablecer contraseña'));
      await tester.pumpAndSettle();

      expect(called, isFalse);
      expect(find.textContaining('no coinciden'), findsOneWidget);
    },
  );

  testWidgets('VerifyEmailScreen auto-submits when token is provided', (
    tester,
  ) async {
    var called = false;
    final client = MockClient((req) async {
      called = true;
      expect(req.body, contains('auto-token'));
      return http.Response('', 204);
    });

    final auth = AuthService(httpClient: client);
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: VerifyEmailScreen(auth: auth, token: 'auto-token'),
      ),
    );

    // Allow the post-frame callback to complete.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(called, isTrue);
    expect(find.textContaining('Verificamos tu email'), findsOneWidget);
  });
}
