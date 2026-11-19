import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/app_info.dart';
import '../models/user.dart';
import '../services/apis.dart';
import '../services/google_auth.dart';
import '../utils/messenger.dart';

/// Signed-in user, app settings from the server, and a "data changed" counter
/// that screens watch to reload after purchases, bookings and bookmarks.
class Session extends ChangeNotifier {
  Session({ApiClient? api, FlutterSecureStorage? storage})
      : api = api ?? ApiClient(),
        _storage = storage ?? FlutterSecureStorage();

  static const _tokenKey = 'li_auth_token';
  static const _userKey = 'li_auth_user';

  final ApiClient api;
  final FlutterSecureStorage _storage;

  AppUser? _user;
  AppInfo _info = AppInfo.fallback;
  bool _ready = false;
  int _version = 0;

  AppUser? get user => _user;
  AppInfo get info => _info;
  bool get isReady => _ready;
  bool get isSignedIn => _user != null;
  int get version => _version;

  Future<void> init() async {
    api.onUnauthorized = _onUnauthorized;
    String? token;
    try {
      token = await _storage.read(key: _tokenKey);
      final cachedUser = await _storage.read(key: _userKey);
      if (token != null && cachedUser != null) {
        final decoded = jsonDecode(cachedUser);
        if (decoded is Map<String, dynamic>) _user = AppUser.fromJson(decoded);
      }
    } catch (_) {
      token = null;
      _user = null;
    }
    api.token = token;
    if (token != null) {
      try {
        _user = await AuthApi(api).me();
        await _saveUser();
      } on ApiException catch (error) {
        if (error.isUnauthorized) await _clear(notify: false);
        // Offline: keep the cached user so the app still opens.
      }
    }
    await refreshInfo(notify: false);
    _ready = true;
    notifyListeners();
  }

  Future<void> refreshInfo({bool notify = true}) async {
    try {
      _info = await CatalogApi(api).appInfo();
      if (notify) notifyListeners();
    } catch (_) {
      // Keep the built-in defaults when the server can't be reached.
    }
  }

  Future<void> signIn(AuthResult result) async {
    api.token = result.token;
    _user = result.user;
    try {
      await _storage.write(key: _tokenKey, value: result.token);
    } catch (_) {
      // The session still works until the app is closed.
    }
    await _saveUser();
    _version++;
    notifyListeners();
  }

  void setUser(AppUser user) {
    _user = user;
    _saveUser();
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await AuthApi(api).logout();
    } catch (_) {
      // Signing out locally is enough if the server can't be reached.
    }
    await GoogleAuth.signOut();
    await _clear();
  }

  /// Removes local session data after the account was deleted on the server.
  Future<void> forget() async {
    await GoogleAuth.signOut();
    await _clear();
  }

  /// Ask open screens to reload (after a purchase, booking, bookmark...).
  void dataChanged() {
    _version++;
    notifyListeners();
  }

  void _onUnauthorized() {
    if (_user == null && api.token == null) return;
    if (_ready) showMessage('Your session has expired. Please sign in again.');
    _clear();
  }

  Future<void> _clear({bool notify = true}) async {
    api.token = null;
    _user = null;
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _userKey);
    } catch (_) {
      // Nothing else to clean up.
    }
    _version++;
    if (notify) notifyListeners();
  }

  Future<void> _saveUser() async {
    final current = _user;
    if (current == null) return;
    try {
      await _storage.write(key: _userKey, value: jsonEncode(current.toJson()));
    } catch (_) {
      // Not critical: the user is fetched again on the next start.
    }
  }
}
