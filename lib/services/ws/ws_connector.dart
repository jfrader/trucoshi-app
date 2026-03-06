import 'package:web_socket_channel/web_socket_channel.dart';

// Conditional import selects the right implementation for IO vs Web.
import 'ws_connector_io.dart'
    if (dart.library.html) 'ws_connector_web.dart' as impl;

WebSocketChannel connectWs(Uri uri, {Map<String, String>? headers}) {
  return impl.connectWs(uri, headers: headers);
}
