import 'package:url_launcher/url_launcher.dart';

import 'messenger.dart';

const _allowedSchemes = {'http', 'https', 'mailto', 'tel'};

/// Opens web links, phone numbers and email addresses outside the app.
Future<void> openLink(String url) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !_allowedSchemes.contains(uri.scheme)) {
    showMessage('This link cannot be opened.');
    return;
  }
  try {
    final opened = await launchUrl(
      uri,
      mode: uri.scheme.startsWith('http') ? LaunchMode.externalApplication : LaunchMode.platformDefault,
    );
    if (!opened) showMessage('Could not open the link.');
  } catch (_) {
    showMessage('Could not open the link.');
  }
}

Future<void> callPhone(String phone) => openLink('tel:${phone.replaceAll(RegExp(r'[^0-9+]'), '')}');

Future<void> sendEmail(String email) => openLink('mailto:$email');
