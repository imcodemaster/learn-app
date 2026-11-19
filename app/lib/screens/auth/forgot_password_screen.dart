import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../services/apis.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../utils/messenger.dart';
import '../../utils/validators.dart';

/// Email → 6-digit code → new password. Pops with `true` once signed in.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _codeSent = false;
  bool _busy = false;
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final problem = validateEmail(_email.text);
    if (problem != null) {
      setState(() => _errors = {'email': problem});
      return;
    }
    final session = context.read<Session>();
    setState(() {
      _busy = true;
      _errors = const {};
    });
    try {
      await AuthApi(session.api).forgotPassword(_email.text.trim());
      if (mounted) setState(() => _codeSent = true);
      showMessage('If an account exists for this email, a code is on its way.');
    } on ApiException catch (error) {
      if (mounted) setState(() => _errors = error.fields);
      showMessage(error.message);
    } catch (error) {
      showMessage(errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    setState(() => _errors = const {});
    if (!(_form.currentState?.validate() ?? false)) return;
    final session = context.read<Session>();
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final result = await AuthApi(session.api).resetPassword(
        email: _email.text.trim(),
        code: _code.text.trim(),
        password: _password.text,
      );
      await session.signIn(result);
      showMessage('Password changed. You’re signed in.');
      if (mounted) navigator.pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _errors = error.fields);
      showMessage(error.message);
    } catch (error) {
      showMessage(errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              _codeSent
                  ? 'Enter the 6-digit code from your email and choose a new password.'
                  : 'Enter your account email. We’ll send you a 6-digit code.',
              style: const TextStyle(color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _email,
              enabled: !_codeSent,
              keyboardType: TextInputType.emailAddress,
              decoration: fieldDecoration('Email address', icon: Icons.mail_outline, error: _errors['email']),
              validator: validateEmail,
            ),
            if (_codeSent) ...[
              const SizedBox(height: 14),
              TextFormField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: fieldDecoration('6-digit code', icon: Icons.pin_outlined, error: _errors['code']),
                validator: validateOtp,
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: fieldDecoration('New password',
                    icon: Icons.lock_reset,
                    error: _errors['password'],
                    hint: 'At least 8 characters, letters and numbers'),
                validator: validatePassword,
              ),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _busy ? null : (_codeSent ? _reset : _sendCode),
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(_codeSent ? 'Set new password' : 'Send code'),
            ),
            if (_codeSent)
              TextButton(
                onPressed: _busy ? null : _sendCode,
                child: const Text('Send a new code'),
              ),
          ],
        ),
      ),
    );
  }
}
