import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../services/apis.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../utils/messenger.dart';
import '../../utils/validators.dart';

/// Asks students who signed in with a phone number for their name.
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _name = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final session = context.read<Session>();
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final user = await AuthApi(session.api).updateName(_name.text.trim());
      session.setUser(user);
      if (mounted) navigator.pop();
    } catch (error) {
      showMessage(errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your name'),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Skip'))],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('What should we call you?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Your name appears on your bookings and course certificates.',
                style: TextStyle(color: AppColors.muted, height: 1.4)),
            const SizedBox(height: 24),
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: fieldDecoration('Full name', icon: Icons.person_outline),
              validator: validateName,
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
