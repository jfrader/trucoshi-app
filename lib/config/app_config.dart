class AppConfig {
  /// Base HTTP URL for the backend, e.g. `http://localhost:8080`.
  ///
  /// Override at build/run time:
  /// `flutter run --dart-define=TRUCOSHI_BACKEND_URL=http://10.0.2.2:8080`
  static const backendBaseUrl = String.fromEnvironment(
    'TRUCOSHI_BACKEND_URL',
    defaultValue: 'http://localhost:2992',
  );

  /// WebSocket URL derived from [backendBaseUrl], e.g. `ws://localhost:8080/v2/ws`.
  static Uri wsV2Uri() {
    final base = Uri.parse(backendBaseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return base.replace(scheme: scheme, path: '/v2/ws');
  }
}
