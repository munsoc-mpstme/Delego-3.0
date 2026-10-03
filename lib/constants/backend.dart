class Backend {
  /// The server the app talks to. Override per run to test against another one:
  ///   flutter run --dart-define=API_BASE_URL=http://localhost:8000   (with adb reverse)
  ///   flutter run --dart-define=API_BASE_URL=http://192.168.1.3:8000 (same Wi-Fi)
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://mundra.onrender.com',
  );
}
