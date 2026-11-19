final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _indianMobile = RegExp(r'^[6-9]\d{9}$');

String? validateName(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Enter your name.';
  if (text.length > 120) return 'Name is too long.';
  return null;
}

String? validateEmail(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Enter your email address.';
  if (!_email.hasMatch(text)) return 'Enter a valid email address.';
  return null;
}

String? validatePassword(String? value) {
  final text = value ?? '';
  if (text.length < 8) return 'Use at least 8 characters.';
  if (!RegExp(r'[A-Za-z]').hasMatch(text) || !RegExp(r'\d').hasMatch(text)) {
    return 'Use both letters and numbers.';
  }
  return null;
}

/// Accepts "98765 43210" or "+91 9876543210"; returns 10 digits or null.
String? normalizeMobile(String value) {
  var digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 12 && digits.startsWith('91')) digits = digits.substring(2);
  if (digits.length == 11 && digits.startsWith('0')) digits = digits.substring(1);
  return _indianMobile.hasMatch(digits) ? digits : null;
}

String? validateMobile(String? value) =>
    normalizeMobile(value ?? '') == null ? 'Enter a valid 10-digit mobile number.' : null;

String? validateOtp(String? value) =>
    RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '') ? null : 'Enter the 6-digit code.';
