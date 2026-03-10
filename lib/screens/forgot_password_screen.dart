import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';
import '../widgets/status_banner.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _busy = false;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() {
        _statusMessage = 'Ingresá el email asociado a tu cuenta.';
        _statusIsError = true;
      });
      return;
    }

    setState(() {
      _busy = true;
      _statusMessage = null;
    });

    final err = await widget.auth.forgotPassword(email);
    if (!mounted) return;

    setState(() {
      _busy = false;
      if (err == null) {
        _statusMessage =
            'Te enviamos un email con instrucciones para restablecer tu contraseña. Revisá bandeja y spam.';
        _statusIsError = false;
      } else {
        _statusMessage = err;
        _statusIsError = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Restablecer contraseña')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ingresá tu email y te enviaremos un link para crear una nueva contraseña.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  enabled: !_busy,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(
                    _busy ? 'Enviando…' : 'Enviar email de restablecimiento',
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          if (!mounted) return;
                          context.go('/login');
                        },
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
