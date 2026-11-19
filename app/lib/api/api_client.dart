import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'api_exception.dart';

/// Talks JSON to the Django backend and adds the sign-in token.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Current session token ("li_..."), or null when signed out.
  String? token;

  /// Called when the server says the session is no longer valid.
  void Function()? onUnauthorized;

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]) =>
      _send('POST', path, body: body ?? const <String, dynamic>{});

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) =>
      _send('PATCH', path, body: body);

  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);

  Uri _uri(String path, Map<String, String>? query) {
    final uri = Uri.parse('${AppConfig.baseUrl}$path');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final request = http.Request(method, _uri(path, query));
    request.headers['Accept'] = 'application/json';
    final sentToken = token;
    if (sentToken != null) request.headers['Authorization'] = 'Bearer $sentToken';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(const Duration(seconds: 25));
      response = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw ApiException.network('The server is taking too long to respond. Please try again.');
    } on SocketException {
      throw ApiException.network('No internet connection. Check your network and try again.');
    } on HandshakeException {
      throw ApiException.network('A secure connection could not be made. Please try again.');
    } on http.ClientException {
      throw ApiException.network('Could not reach the server. Please try again.');
    }

    Map<String, dynamic> decoded = <String, dynamic>{};
    if (response.bodyBytes.isNotEmpty) {
      try {
        final value = jsonDecode(utf8.decode(response.bodyBytes));
        if (value is Map<String, dynamic>) decoded = value;
      } on FormatException {
        // Not JSON (for example an HTML error page from a proxy).
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;

    final error = decoded['error'];
    var code = 'http_${response.statusCode}';
    var message = 'Something went wrong (error ${response.statusCode}). Please try again.';
    final fields = <String, String>{};
    if (error is Map) {
      code = '${error['code'] ?? code}';
      message = '${error['message'] ?? message}';
      final rawFields = error['fields'];
      if (rawFields is Map) {
        rawFields.forEach((key, value) => fields['$key'] = '$value');
      }
    }
    if (response.statusCode == 401 && sentToken != null && sentToken == token) {
      onUnauthorized?.call();
    }
    throw ApiException(status: response.statusCode, code: code, message: message, fields: fields);
  }
}
