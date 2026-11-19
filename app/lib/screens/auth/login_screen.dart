import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../models/user.dart';
import '../../services/apis.dart';
import '../../services/google_auth.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../utils/links.dart';
import '../../utils/messenger.dart';
import 'complete_profile_screen.dart';
import 'email_auth_screen.dart';
import 'phone_login_screen.dart';

/// Choose how to sign in. Pops with `true` once signed in.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.reason});

  final String? reason;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _googleBusy = false;

  @override
  Widget build(BuildContext context) {
    final info = context.watch<Session>().info;
    final showGoogle = GoogleAuth.isConfigured && info.googleEnabled;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset('assets/images/logo.png', width: 84, height: 84),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Welcome to LearnInCreation',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              widget.reason ?? 'Sign in to enroll in courses, save favourites and book study-center seats.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 32),
            if (showGoogle) ...[
              OutlinedButton(
                onPressed: _googleBusy ? null : _google,
                child: _googleBusy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _GoogleMark(),
                          SizedBox(width: 12),
                          Text('Continue with Google'),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: () => _open(const PhoneLoginScreen()),
              icon: const Icon(Icons.phone_iphone),
              label: const Text('Continue with mobile number'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _open(const EmailAuthScreen()),
              icon: const Icon(Icons.mail_outline),
              label: const Text('Continue with email'),
            ),
            const SizedBox(height: 28),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('By continuing you agree to our ', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                InkWell(
                  onTap: () => openLink(info.termsUrl),
                  child: const Text('Terms', style: TextStyle(color: AppColors.primary, fontSize: 12.5)),
                ),
                const Text(' and ', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                InkWell(
                  onTap: () => openLink(info.privacyUrl),
                  child: const Text('Privacy policy', style: TextStyle(color: AppColors.primary, fontSize: 12.5)),
                ),
                const Text('.', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(Widget screen) async {
    final navigator = Navigator.of(context);
    final signedIn = await navigator.push<bool>(MaterialPageRoute(builder: (_) => screen));
    if (signedIn == true && mounted) navigator.pop(true);
  }

  Future<void> _google() async {
    final session = context.read<Session>();
    final navigator = Navigator.of(context);
    setState(() => _googleBusy = true);
    try {
      final idToken = await GoogleAuth.idToken();
      if (idToken == null) return; // closed the Google window
      final result = await AuthApi(session.api).google(idToken);
      await session.signIn(result);
      if (!mounted) return;
      await finishSignIn(navigator, result);
    } on ApiException catch (error) {
      showMessage(error.message);
    } catch (_) {
      showMessage('Google sign-in didn’t work. Please try again or use another option.');
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }
}

/// Asks new phone/Google users for their name, then closes the sign-in flow.
Future<void> finishSignIn(NavigatorState navigator, AuthResult result) async {
  if (result.user.needsName) {
    await navigator.push(MaterialPageRoute(builder: (_) => const CompleteProfileScreen()));
  }
  showMessage('Signed in as ${result.user.displayName}.');
  navigator.pop(true);
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
      child: const Text('G', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF4285F4), fontSize: 15)),
    );
  }
}
