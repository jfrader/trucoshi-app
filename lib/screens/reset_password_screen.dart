import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';
import '../widgets/status_banner.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.auth,
    required this.token,
  });

  final AuthService auth;
  final String token;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _busy = false;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    if (widget.token.isEmpty) {
      _statusMessage = 'El link no incluye un token válido.';
      _statusIsError = true;
    }
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final token = widget.token.trim();
    if (token.isEmpty) {
      setState(() {
        _statusMessage =
            'Necesitamos el token del email para resetear tu contraseña.';
        _statusIsError = true;
      });
      return;
    }

    final pw = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;

    if (pw.length < 8) {
      setState(() {
        _statusMessage =
            'La nueva contraseña debe tener al menos 8 caracteres.';
        _statusIsError = true;
      });
      return;
    }

    if (pw != confirm) {
      setState(() {
        _statusMessage = 'Las contraseñas no coinciden.';
        _statusIsError = true;
      });
      return;
    }

    setState(() {
      _busy = true;
      _statusMessage = null;
    });

    final err = await widget.auth.resetPassword(token: token, password: pw);
    if (!mounted) return;

    setState(() {
      _busy = false;
      if (err == null) {
        _statusMessage =
            'Actualizamos tu contraseña. Iniciá sesión con la nueva clave.';
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
      appBar: AppBar(title: const Text('Elegí una nueva contraseña')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'El link de tu email expira en 30 minutos. Elegí una nueva contraseña para continuar.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nueva contraseña',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  enableSuggestions: false,
                  autofocus: true,
                  enabled: !_busy && !hasSuccess,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Repetí la contraseña',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  enableSuggestions: false,
                  enabled: !_busy && !hasSuccess,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || hasSuccess ? null : _submit,
                  child: Text(_busy ? 'Guardando…' : 'Restablecer contraseña'),
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
