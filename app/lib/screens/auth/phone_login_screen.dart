import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../models/user.dart';
import '../../services/apis.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../utils/messenger.dart';
import '../../utils/validators.dart';
import 'login_screen.dart';

/// Mobile number → 6-digit SMS code. Pops with `true` once signed in.
class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  OtpSent? _sent;
  bool _busy = false;
  String? _phoneError;
  String? _codeError;
  int _resendIn = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startTimer(int seconds) {
    _timer?.cancel();
    setState(() => _resendIn = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendIn = _resendIn > 0 ? _resendIn - 1 : 0);
      if (_resendIn == 0) timer.cancel();
    });
  }

  Future<void> _send() async {
    final phone = normalizeMobile(_phone.text);
    if (phone == null) {
      setState(() => _phoneError = 'Enter a valid 10-digit mobile number.');
      return;
    }
    final session = context.read<Session>();
    setState(() {
      _busy = true;
      _phoneError = null;
    });
    try {
      final sent = await AuthApi(session.api).sendOtp(phone);
      if (!mounted) return;
      setState(() => _sent = sent);
      _startTimer(sent.resendIn);
    } on ApiException catch (error) {
      if (mounted) setState(() => _phoneError = error.fields['phone'] ?? error.message);
    } catch (error) {
      showMessage(errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final sent = _sent;
    if (sent == null) return;
    final problem = validateOtp(_code.text);
    if (problem != null) {
      setState(() => _codeError = problem);
      return;
    }
    final session = context.read<Session>();
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _codeError = null;
    });
    try {
      final result = await AuthApi(session.api).verifyOtp(phone: sent.phone, code: _code.text.trim());
      await session.signIn(result);
      if (!mounted) return;
      await finishSignIn(navigator, result);
    } on ApiException catch (error) {
      if (mounted) setState(() => _codeError = error.fields['code'] ?? error.message);
    } catch (error) {
      showMessage(errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sent = _sent;
    return Scaffold(
      appBar: AppBar(title: const Text('Mobile number')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: sent == null ? _phoneStep() : _codeStep(sent),
        ),
      ),
    );
  }

  List<Widget> _phoneStep() => [
        const Text('Sign in with your mobile number',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('We’ll send a 6-digit code by SMS. New here? An account is created automatically.',
            style: TextStyle(color: AppColors.muted, height: 1.4)),
        const SizedBox(height: 24),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          autofocus: true,
          autofillHints: const [AutofillHints.telephoneNumberNational],
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(16)],
          decoration: fieldDecoration('Mobile number', icon: Icons.phone_iphone, prefixText: '+91 ', error: _phoneError),
          onSubmitted: (_) => _send(),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _send,
          child: _busy ? const _Spinner() : const Text('Send code'),
        ),
      ];

  List<Widget> _codeStep(OtpSent sent) => [
        const Text('Enter the code', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('We sent a 6-digit code to ${sent.phone}.', style: const TextStyle(color: AppColors.muted, height: 1.4)),
        if (sent.debugCode != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: cardDecoration(color: AppColors.warningSoft, border: const Color(0xFFFDE68A)),
            child: Text('Test mode (no SMS provider set up): your code is ${sent.debugCode}',
                style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600)),
          ),
        ],
        const SizedBox(height: 24),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          autofocus: true,
          autofillHints: const [AutofillHints.oneTimeCode],
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w700),
          decoration: fieldDecoration('6-digit code', icon: Icons.sms_outlined, error: _codeError),
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _verify,
          child: _busy ? const _Spinner() : const Text('Verify and continue'),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      _timer?.cancel();
                      setState(() {
                        _sent = null;
                        _code.clear();
                        _codeError = null;
                      });
                    },
              child: const Text('Change number'),
            ),
            TextButton(
              onPressed: _busy || _resendIn > 0 ? null : _send,
              child: Text(_resendIn > 0 ? 'Resend in ${_resendIn}s' : 'Resend code'),
            ),
          ],
        ),
      ];
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5));
}
