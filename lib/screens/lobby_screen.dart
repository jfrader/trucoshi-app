import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lobby'),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: () => auth.logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Lobby placeholder (WS connect comes next).'),
      ),
    );
  }
}
