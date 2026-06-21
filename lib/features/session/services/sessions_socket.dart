import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../core/constants/api_endpoints.dart';

/// Shared Socket.IO endpoint derivation + builder for the Nest gateways.
///
/// Both the live-session feed (`/sessions`) and the credits feed (`/payments`)
/// dial the same host/proxy path; this keeps that derivation in one place so
/// they can never drift. The web app resolves a relative URL against
/// window.origin, but Flutter must dial an absolute origin — a bare `/sessions`
/// has no host and just times out.
class SessionsSocket {
  SessionsSocket._();

  /// Origin (`scheme://host[:port]`) derived from [ApiEndpoints.nodeBaseUrl].
  static String get _origin {
    final restUri = Uri.parse(ApiEndpoints.nodeBaseUrl);
    return '${restUri.scheme}://${restUri.host}'
        '${restUri.hasPort ? ':${restUri.port}' : ''}';
  }

  /// Any path segment BEFORE `hydrawav/v1` (e.g. `/api`) is a reverse-proxy
  /// prefix that also fronts socket.io, so the external socket path is
  /// `<proxyPrefix>/socket.io`.
  static String get _proxyPrefix {
    final restUri = Uri.parse(ApiEndpoints.nodeBaseUrl);
    return restUri.path
        .split('hydrawav/v1')
        .first
        .replaceAll(RegExp(r'/+$'), ''); // e.g. `/api` or ``
  }

  /// Build a configured, NOT-yet-connected socket for the given gateway
  /// [namespace] (e.g. `/sessions` or `/payments`). Call `.connect()` after
  /// wiring handlers, then [subscribeOrganization] on connect.
  static io.Socket buildSocket({
    required String? token,
    required String namespace,
  }) {
    final socketUrl = '$_origin$namespace';
    final socketPath = '$_proxyPrefix/socket.io';
    return io.io(
      socketUrl,
      io.OptionBuilder()
          .setPath(socketPath)
          .setTransports(['websocket', 'polling'])
          .setAuth({'token': token})
          // ngrok free tier injects a browser-warning page that breaks the
          // socket.io handshake unless this header is present.
          .setExtraHeaders({'ngrok-skip-browser-warning': 'true'})
          .disableAutoConnect()
          .enableForceNew()
          .build(),
    );
  }

  /// Join the org room so the server's room-scoped broadcasts reach this
  /// client. Safe to call on every (re)connect.
  static void subscribeOrganization(io.Socket socket, String? orgId) {
    final id = int.tryParse(orgId ?? '');
    if (id != null) {
      socket.emit('subscribe-organization', {'organizationId': id});
    }
  }

  /// Convenience: `'$origin/sessions'`-style URL for logging.
  static String urlFor(String namespace) => '$_origin$namespace';

  /// Convenience: the socket.io path including any proxy prefix, for logging.
  static String get path => '$_proxyPrefix/socket.io';
}
