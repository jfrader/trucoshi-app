import 'package:flutter/foundation.dart';

/// Small abstraction for platform-specific product constraints.
///
/// Today the biggest one is WS auth:
/// - Mobile/desktop can send `Authorization` headers when opening the socket.
/// - Browsers cannot (no custom headers for WebSocket connections).
class PlatformCaps {
  const PlatformCaps({required this.supportsWsAuthHeaders});

  /// Whether the platform can send custom headers when opening a WebSocket.
  final bool supportsWsAuthHeaders;

  factory PlatformCaps.current() {
    return const PlatformCaps(supportsWsAuthHeaders: !kIsWeb);
  }
}
