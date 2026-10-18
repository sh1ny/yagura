import 'dart:async';
import 'dart:io';

import 'package:http2/transport.dart';

import 'pressure.dart';

/// Opens the listener of a secure server; a seam so tests can make a bind
/// fail.
typedef ListenerBinder = Future<SecureListener> Function(
  YaguraGrpcServer server,
  InternetAddress address,
  int port,
  SecurityContext context,
);

/// A TLS listener in client-certificate request mode that hands each
/// connection to a [YaguraGrpcServer].
///
/// package:grpc's own `serve` cannot be closed without waiting for every
/// open stream and gives no way to drop them, and the certificate rotation
/// (design D4) has to close the listener, serve again with the new
/// certificate and drop the connections that still use the old one.
class SecureListener {
  SecureListener._(this._server, this._socket);

  final YaguraGrpcServer _server;
  final SecureServerSocket _socket;
  final _sockets = <Socket>{};

  int get port => _socket.port;

  static Future<SecureListener> bind(
    YaguraGrpcServer server,
    InternetAddress address,
    int port,
    SecurityContext context,
  ) async {
    final socket = await SecureServerSocket.bind(
      address,
      port,
      context,
      requestClientCertificate: true,
    );
    final listener = SecureListener._(server, socket);
    socket.listen(
      listener._accept,
      // A client that fails the handshake (another CA, an expired
      // certificate) is not an error of the listener.
      onError: (Object _) {},
    );
    return listener;
  }

  void _accept(SecureSocket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    InternetAddress? remote;
    try {
      remote = socket.remoteAddress;
    } on Object {
      // The peer is already gone.
    }
    final connection = ServerTransportConnection.viaSocket(socket);
    _sockets.add(socket);
    unawaited(
      socket.done.then<void>(
        (_) => _sockets.remove(socket),
        onError: (Object _) => _sockets.remove(socket),
      ),
    );
    unawaited(
      _server.serveConnection(
        connection: connection,
        clientCertificate: socket.peerCertificate,
        remoteAddress: remote,
      ),
    );
  }

  /// Stops accepting. With [dropConnections] the open connections end too;
  /// their clients reconnect.
  Future<void> close({bool dropConnections = false}) async {
    await _socket.close();
    if (dropConnections) {
      // The socket, not the HTTP/2 connection: terminating the connection
      // asserts in package:http2 while streams still hold queued messages.
      for (final socket in [..._sockets]) {
        socket.destroy();
      }
      _sockets.clear();
    }
  }
}
