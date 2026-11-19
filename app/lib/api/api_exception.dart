/// An error from the backend (or the network) with a message safe to show.
class ApiException implements Exception {
  ApiException({
    required this.status,
    required this.code,
    required this.message,
    this.fields = const {},
  });

  factory ApiException.network(String message) =>
      ApiException(status: 0, code: 'network', message: message);

  final int status;
  final String code;
  final String message;
  final Map<String, String> fields;

  bool get isUnauthorized => status == 401;
  bool get isNetwork => status == 0;

  @override
  String toString() => message;
}

/// Turns any error into a friendly sentence.
String errorText(Object error) {
  if (error is ApiException) return error.message;
  return 'Something went wrong. Please try again.';
}
