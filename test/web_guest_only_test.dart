import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trucoshi_app/app/app.dart';
import 'package:trucoshi_app/platform/platform_caps.dart';
import 'package:trucoshi_app/screens/login_screen.dart';
import 'package:trucoshi_app/services/auth_service.dart';

void main() {
  testWidgets(
    'Lobby hides login controls when WS auth headers are unsupported',
    (tester) async {
      await tester.pumpWidget(
        const TrucoshiApp(
          platformCaps: PlatformCaps(supportsWsAuthHeaders: false),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Login / Register'), findsNothing);
      expect(find.byIcon(Icons.login), findsNothing);
      expect(find.textContaining('guest-only'), findsOneWidget);
    },
  );

  testWidgets(
    'LoginScreen renders guest-only UX when WS auth headers are unsupported',
    (tester) async {
      final auth = AuthService();

      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            auth: auth,
            caps: const PlatformCaps(supportsWsAuthHeaders: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Web is guest-only for now.'), findsOneWidget);
      expect(find.byType(SegmentedButton<bool>), findsNothing);
      expect(find.text('Use token'), findsNothing);
      expect(find.text('Continue as guest'), findsOneWidget);
    },
  );
}
