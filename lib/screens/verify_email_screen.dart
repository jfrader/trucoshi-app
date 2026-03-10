import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';
import '../widgets/status_banner.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, required this.auth, required this.token});

  final AuthService auth;
  final String token;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  late final TextEditingController _tokenCtrl;
  bool _busy = false;
  String? _statusMessage;
  bool _statusIsError = false;
  bool _autoSubmitted = false;

  @override
  void initState() {
    super.initState();
    _tokenCtrl = TextEditingController(text: widget.token);

    if (widget.token.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _autoSubmitted = true;
          _submit();
        }
      });
    }
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) {
      setState(() {
        _statusMessage =
            'Pegá el token del email o abrí directamente el link "verify-email" para continuar.';
        _statusIsError = true;
      });
      return;
    }

    setState(() {
      _busy = true;
      if (!_autoSubmitted) {
        _statusMessage = null;
      }
      _autoSubmitted = false;
    });

    final err = await widget.auth.verifyEmail(token);
    if (!mounted) return;

    setState(() {
      _busy = false;
      if (err == null) {
        _statusMessage = '¡Listo! Verificamos tu email.';
        _statusIsError = false;
      } else {
        _statusMessage = err;
        _statusIsError = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasSuccess = _statusMessage != null && !_statusIsError;

    return Scaffold(
      appBar: AppBar(title: const Text('Verificar email')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Abrí el link desde el email o pegá el token manualmente para confirmar tu cuenta.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _tokenCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Token',
                    border: OutlineInputBorder(),
                  ),
                  autocorrect: false,
                  enableSuggestions: false,
                  enabled: !_busy && !hasSuccess,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || hasSuccess ? null : _submit,
                  child: Text(_busy ? 'Verificando…' : 'Verificar email'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Volver al inicio de sesión'),
                ),
                const SizedBox(height: 16),
                if (_statusMessage != null)
                  _statusIsError
                      ? StatusBanner.error(_statusMessage!)
                      : StatusBanner.success(_statusMessage!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
