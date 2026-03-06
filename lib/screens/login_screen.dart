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

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
    });

    try {
      if (_registerMode) {
        await widget.auth.register(
          email: _emailCtrl.text,
          password: _passwordCtrl.text,
          name: _nameCtrl.text,
        );
      } else {
        await widget.auth.login(
          email: _emailCtrl.text,
          password: _passwordCtrl.text,
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
              controller: _emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            if (_registerMode) ...[
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _passwordCtrl,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
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
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () {
                      widget.auth.continueAsGuest();
                    },
              child: const Text('Continue as guest'),
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
