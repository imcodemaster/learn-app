/// Build-time settings. Pass them when building, for example:
///
///   flutter build apk --release \
///     --dart-define=API_BASE_URL=https://api.learnincreation.com \
///     --dart-define=GOOGLE_SERVER_CLIENT_ID=1234-abc.apps.googleusercontent.com
class AppConfig {
  AppConfig._();

  /// Address of the Django backend (no trailing slash).
  /// The default points at your computer from the Android emulator.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Google OAuth *Web* client ID (the backend's GOOGLE_CLIENT_IDS value).
  /// Leave empty to hide the "Continue with Google" button.
  static const String googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static const String appName = 'LearnInCreation';
  static const String version = '1.0.0';

  static String get baseUrl =>
      apiBaseUrl.endsWith('/') ? apiBaseUrl.substring(0, apiBaseUrl.length - 1) : apiBaseUrl;
}
