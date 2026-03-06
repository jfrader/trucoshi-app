import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/lobby_screen.dart';
import '../screens/login_screen.dart';
import '../screens/match_screen.dart';
import '../screens/table_screen.dart';
import '../services/auth_service.dart';
import '../services/ws/ws_service.dart';

class TrucoshiApp extends StatefulWidget {
  const TrucoshiApp({super.key});

  @override
  State<TrucoshiApp> createState() => _TrucoshiAppState();
}

class _TrucoshiAppState extends State<TrucoshiApp> {
  late final AuthService _auth;
  late final WsService _ws;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();

    _auth = AuthService();
    _ws = WsService(auth: _auth);

    _router = GoRouter(
      initialLocation: '/lobby',
      refreshListenable: _auth,
      redirect: (context, state) {
        final loggedIn = _auth.isLoggedIn;
        final goingToLogin = state.matchedLocation == '/login';
        final isTableOrMatch =
            state.matchedLocation.startsWith('/match') || state.matchedLocation.startsWith('/table');

        if (!loggedIn && isTableOrMatch) return '/lobby';
        if (loggedIn && goingToLogin) return '/lobby';
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => LoginScreen(auth: _auth),
        ),
        GoRoute(
          path: '/lobby',
          builder: (context, state) => LobbyScreen(auth: _auth, ws: _ws),
        ),
        GoRoute(
          path: '/match/:id',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return MatchScreen(ws: _ws, matchId: id);
          },
        ),
        GoRoute(
          path: '/table/:id',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return TableScreen(ws: _ws, matchId: id);
          },
        ),
      ],
    );
  }

  @override
  void dispose() {
    _ws.dispose();
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Trucoshi',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
