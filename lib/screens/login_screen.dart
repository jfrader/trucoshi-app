import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController(text: 'test@example.com');
  final _passwordCtrl = TextEditingController(text: 'test1234');
  final _nameCtrl = TextEditingController(text: 'Test');

  bool _registerMode = false;
  bool _busy = false;

  Future<void> _showTokenDialog() async {
    final tokenCtrl = TextEditingController();
    final nameCtrl = TextEditingController(text: _nameCtrl.text);

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Use access token'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Display name (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tokenCtrl,
                decoration: const InputDecoration(
                  labelText: 'access_token',
                  border: OutlineInputBorder(),
                ),
                autocorrect: false,
                enableSuggestions: false,
              ),
              const SizedBox(height: 8),
              const Text(
                'Dev: pasting a token skips /v1/auth/login and only affects WS auth.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Use token'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    final token = tokenCtrl.text.trim();
    if (token.isEmpty) return;

    widget.auth.useToken(token, displayName: nameCtrl.text);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final name = _nameCtrl.text.trim();

    if (_registerMode) {
      if (email.isEmpty || password.isEmpty || name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email, password, and name are required to register.')),
        );
        return;
      }
    } else {
      if (email.isEmpty || password.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email and password are required to login.')),
        );
        return;
      }
    }

    setState(() {
      _busy = true;
    });

    try {
      if (_registerMode) {
        await widget.auth.register(
          email: email,
          password: password,
          name: name,
        );
      } else {
        await widget.auth.login(
          email: email,
          password: password,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final err = widget.auth.lastError;

    return Scaffold(
      appBar: AppBar(title: const Text('Trucoshi - Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Login')),
                      ButtonSegment(value: true, label: Text('Register')),
                    ],
                    selected: {_registerMode},
                    onSelectionChanged: _busy
                        ? null
                        : (set) {
                            setState(() {
                              _registerMode = set.first;
                            });
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Display name',
                helperText: 'Used for guest + match join/create. Login name comes from the server.',
                border: OutlineInputBorder(),
              ),
              enabled: !_busy,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Email',
                helperText: 'Required for login/register.',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              enabled: !_busy,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              decoration: const InputDecoration(
                labelText: 'Password',
                helperText: 'Required for login/register.',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              enabled: !_busy,
            ),
            const SizedBox(height: 12),
            if (err != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  err,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy
                  ? 'Working…'
                  : (_registerMode ? 'Create account' : 'Login')),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () {
                            widget.auth.continueAsGuest(
                              displayName: _nameCtrl.text,
                            );
                          },
                    child: const Text('Continue as guest'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _showTokenDialog,
                    child: const Text('Use token'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Dev note: backend URL comes from --dart-define=TRUCOSHI_BACKEND_URL',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
