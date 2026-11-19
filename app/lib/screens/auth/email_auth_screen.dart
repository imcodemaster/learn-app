import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../services/apis.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../utils/messenger.dart';
import '../../utils/validators.dart';
import 'forgot_password_screen.dart';
import 'login_screen.dart';

/// Email + password: sign in or create an account. Pops with `true` once signed in.
class EmailAuthScreen extends StatefulWidget {
  const EmailAuthScreen({super.key});

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  final _signInForm = GlobalKey<FormState>();
  final _registerForm = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool register}) async {
    setState(() => _errors = const {});
    final form = register ? _registerForm : _signInForm;
    if (!(form.currentState?.validate() ?? false)) return;
    final session = context.read<Session>();
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final api = AuthApi(session.api);
      final result = register
          ? await api.register(name: _name.text.trim(), email: _email.text.trim(), password: _password.text)
          : await api.login(email: _email.text.trim(), password: _password.text);
      await session.signIn(result);
      if (!mounted) return;
      await finishSignIn(navigator, result);
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Email'),
          bottom: const TabBar(tabs: [Tab(text: 'Sign in'), Tab(text: 'Create account')]),
        ),
        body: TabBarView(
          children: [
            Form(
              key: _signInForm,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  _emailField(),
                  const SizedBox(height: 14),
                  _passwordField(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy ? null : _forgotPassword,
                      child: const Text('Forgot password?'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _busy ? null : () => _submit(register: false),
                    child: _busy ? const _Spinner() : const Text('Sign in'),
                  ),
                ],
              ),
            ),
            Form(
              key: _registerForm,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    decoration: fieldDecoration('Full name', icon: Icons.person_outline, error: _errors['name']),
                    validator: validateName,
                  ),
                  const SizedBox(height: 14),
                  _emailField(),
                  const SizedBox(height: 14),
                  _passwordField(newPassword: true),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _busy ? null : () => _submit(register: true),
                    child: _busy ? const _Spinner() : const Text('Create account'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emailField() => TextFormField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: fieldDecoration('Email address', icon: Icons.mail_outline, error: _errors['email']),
        validator: validateEmail,
      );

  Widget _passwordField({bool newPassword = false}) => TextFormField(
        controller: _password,
        obscureText: !_showPassword,
        autofillHints: [newPassword ? AutofillHints.newPassword : AutofillHints.password],
        decoration: fieldDecoration(
          'Password',
          icon: Icons.lock_outline,
          error: _errors['password'],
          hint: newPassword ? 'At least 8 characters, letters and numbers' : null,
          suffix: IconButton(
            icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
        ),
        validator: newPassword ? validatePassword : (value) => (value == null || value.isEmpty) ? 'Enter your password.' : null,
      );

  Future<void> _forgotPassword() async {
    final navigator = Navigator.of(context);
    final signedIn = await navigator.push<bool>(MaterialPageRoute(
      builder: (_) => ForgotPasswordScreen(initialEmail: _email.text.trim()),
    ));
    if (signedIn == true && mounted) navigator.pop(true);
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5));
}
