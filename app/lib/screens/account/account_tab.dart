import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../config.dart';
import '../../services/apis.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../utils/auth_guard.dart';
import '../../utils/links.dart';
import '../../utils/messenger.dart';
import '../../widgets/common.dart';
import '../studycenter/my_bookings_screen.dart';
import 'about_screen.dart';
import 'edit_profile_screen.dart';
import 'faq_screen.dart';
import 'payments_screen.dart';

class AccountTab extends StatelessWidget {
  const AccountTab({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final user = session.user;
    final info = session.info;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (user == null)
            CardBox(
              child: Column(
                children: [
                  const Icon(Icons.account_circle_outlined, size: 56, color: AppColors.primary),
                  const SizedBox(height: 10),
                  const Text('Sign in to LearnInCreation',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text('Enroll in courses, save favourites and book study-center seats.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 14),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    onPressed: () => ensureSignedIn(context),
                    child: const Text('Sign in or create account'),
                  ),
                ],
              ),
            )
          else
            CardBox(
              child: Row(
                children: [
                  Avatar(initials: user.initials, imageUrl: user.avatarUrl, radius: 30),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        if (user.contactLine.isNotEmpty)
                          Text(user.contactLine, style: const TextStyle(color: AppColors.muted)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit profile',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _push(context, const EditProfileScreen()),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          if (user != null)
            _Group(children: [
              _Item(Icons.confirmation_number_outlined, 'My bookings', () => _push(context, const MyBookingsScreen())),
              _Item(Icons.receipt_long_outlined, 'Payment history', () => _push(context, const PaymentsScreen())),
              _Item(Icons.person_outline, 'Edit profile', () => _push(context, const EditProfileScreen())),
            ]),
          _Group(children: [
            _Item(Icons.info_outline, 'About ${info.orgName}', () => _push(context, const AboutScreen())),
            _Item(Icons.help_outline, 'FAQ', () => _push(context, const FaqScreen())),
            _Item(Icons.call_outlined, 'Call us', () => callPhone(info.phone)),
            _Item(Icons.mail_outline, 'Email us', () => sendEmail(info.email)),
            _Item(Icons.public, 'Visit our website', () => openLink(info.website)),
          ]),
          _Group(children: [
            _Item(Icons.privacy_tip_outlined, 'Privacy policy', () => openLink(info.privacyUrl)),
            _Item(Icons.description_outlined, 'Terms of use', () => openLink(info.termsUrl)),
          ]),
          if (user != null)
            _Group(children: [
              _Item(Icons.logout, 'Sign out', () => _signOut(context)),
              _Item(Icons.delete_outline, 'Delete my account', () => _deleteAccount(context), danger: true),
            ]),
          const SizedBox(height: 8),
          Center(
            child: Text('${AppConfig.appName} · version ${AppConfig.version}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _signOut(BuildContext context) async {
    final session = context.read<Session>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign in again any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed != true) return;
    await session.signOut();
    showMessage('Signed out.');
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final session = context.read<Session>();
    final controller = TextEditingController();
    final typed = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently removes your profile, course access, progress and saved courses, '
              'and cancels active study-center bookings. Payment records are kept for accounting.\n\n'
              'Type DELETE to confirm.',
            ),
            const SizedBox(height: 12),
            TextField(controller: controller, autofocus: true, decoration: fieldDecoration('Type DELETE')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (typed == null) return;
    if (typed != 'DELETE') {
      showMessage('Type DELETE in capital letters to confirm.');
      return;
    }
    try {
      await AuthApi(session.api).deleteAccount();
      await session.forget();
      showMessage('Your account has been deleted.');
    } catch (error) {
      showMessage(errorText(error));
    }
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item(this.icon, this.label, this.onTap, {this.danger = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.text;
    return ListTile(
      leading: Icon(icon, color: danger ? AppColors.danger : AppColors.primary),
      title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
      onTap: onTap,
    );
  }
}
