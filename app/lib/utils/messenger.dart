import 'package:flutter/material.dart';

/// Lets any part of the app show a short message at the bottom of the screen.
final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

void showMessage(String text, {SnackBarAction? action}) {
  final messenger = messengerKey.currentState;
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), action: action, duration: const Duration(seconds: 4)));
}
