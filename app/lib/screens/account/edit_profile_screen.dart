import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../services/apis.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../utils/messenger.dart';
import '../../utils/validators.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameForm = GlobalKey<FormState>();
  final _passwordForm = GlobalKey<FormState>();
  late final TextEditingController _name;
  final _current = TextEditingController();
  final _new = TextEditingController();
  bool _savingName = false;
  bool _savingPassword = false;
  bool _showPasswords = false;
  Map<String, String> _passwordErrors = const {};

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: context.read<Session>().user?.name ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _current.dispose();
    _new.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user;
    if (user == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Please sign in again.')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Form(
            key: _nameForm,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Your name', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: fieldDecoration('Full name', icon: Icons.person_outline),
                  validator: validateName,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _savingName ? null : _saveName,
                  child: _savingName ? const _Spinner() : const Text('Save name'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          if (user.email != null || user.hasPassword)
            Form(
              key: _passwordForm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(user.hasPassword ? 'Change password' : 'Set a password',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    user.hasPassword
                        ? 'Other devices will be signed out.'
                        : 'Add a password to also sign in with your email address.',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 10),
                  if (user.hasPassword) ...[
                    TextFormField(
                      controller: _current,
                      obscureText: !_showPasswords,
                      decoration: fieldDecoration('Current password',
                          icon: Icons.lock_outline, error: _passwordErrors['current_password']),
                      validator: (value) => (value == null || value.isEmpty) ? 'Enter your current password.' : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _new,
                    obscureText: !_showPasswords,
                    decoration: fieldDecoration(
                      'New password',
                      icon: Icons.lock_reset,
                      error: _passwordErrors['new_password'],
                      hint: 'At least 8 characters, letters and numbers',
                      suffix: IconButton(
                        icon: Icon(_showPasswords ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _showPasswords = !_showPasswords),
                      ),
                    ),
                    validator: validatePassword,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _savingPassword ? null : () => _savePassword(user.hasPassword),
                    child: _savingPassword ? const _Spinner() : const Text('Update password'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _saveName() async {
    if (!(_nameForm.currentState?.validate() ?? false)) return;
    final session = context.read<Session>();
    setState(() => _savingName = true);
    try {
      final user = await AuthApi(session.api).updateName(_name.text.trim());
      session.setUser(user);
      showMessage('Name saved.');
    } catch (error) {
      showMessage(errorText(error));
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _savePassword(bool hasPassword) async {
    setState(() => _passwordErrors = const {});
    if (!(_passwordForm.currentState?.validate() ?? false)) return;
    final session = context.read<Session>();
    setState(() => _savingPassword = true);
    try {
      final user = await AuthApi(session.api).changePassword(
        currentPassword: hasPassword ? _current.text : null,
        newPassword: _new.text,
      );
      session.setUser(user);
      _current.clear();
      _new.clear();
      showMessage('Password updated.');
    } on ApiException catch (error) {
      if (mounted) setState(() => _passwordErrors = error.fields);
      showMessage(error.message);
    } catch (error) {
      showMessage(errorText(error));
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5));
}
