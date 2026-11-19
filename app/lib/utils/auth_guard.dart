import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/auth/login_screen.dart';
import '../state/session.dart';

/// Makes sure a student is signed in; opens the sign-in screen if not.
/// Returns true when signed in afterwards.
Future<bool> ensureSignedIn(BuildContext context, {String? reason}) async {
  final session = context.read<Session>();
  if (session.isSignedIn) return true;
  final navigator = Navigator.of(context);
  await navigator.push<bool>(MaterialPageRoute(builder: (_) => LoginScreen(reason: reason)));
  return session.isSignedIn;
}
