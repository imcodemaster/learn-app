import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_shell.dart';
import 'screens/splash_screen.dart';
import 'state/session.dart';
import 'theme.dart';
import 'utils/messenger.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final session = Session();
  runApp(ChangeNotifierProvider<Session>.value(value: session, child: const LearnInCreationApp()));
  session.init();
}

class LearnInCreationApp extends StatelessWidget {
  const LearnInCreationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LearnInCreation',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      scaffoldMessengerKey: messengerKey,
      home: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final ready = context.select<Session, bool>((session) => session.isReady);
    return ready ? const HomeShell() : const SplashScreen();
  }
}
