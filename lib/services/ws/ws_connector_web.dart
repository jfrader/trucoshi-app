import 'package:web_socket_channel/html.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectWs(Uri uri, {Map<String, String>? headers}) {
  // Browsers don't support custom headers for WebSocket connections.
  // If needed later, move auth to query params or cookies.
  return HtmlWebSocketChannel.connect(uri);
}
