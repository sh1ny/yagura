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

/// Bounds on the connections of the network-facing listener. Anyone who can
/// reach the port may open a connection without a certificate (request mode
/// lets the handshake through so pairing works), so what such a connection
/// can hold is limited.
class ListenerLimits {
  const ListenerLimits({
    this.maxConnections = 256,
    this.handshakeTimeout = const Duration(seconds: 10),
    this.idleTimeout = const Duration(seconds: 30),
  });

  /// Open connections, authenticated or not; a further one is closed at once.
  final int maxConnections;

  /// From accept to the end of the TLS handshake.
  final Duration handshakeTimeout;

  /// Without a byte from the peer, for a connection that presented no client
  /// certificate (it can only pair). Connections with a certificate rely on
  /// HTTP/2 keepalive.
  final Duration idleTimeout;
}

/// A TLS listener in client-certificate request mode that hands each
/// connection to a [YaguraGrpcServer].
///
/// package:grpc's own `serve` cannot be closed without waiting for every
/// open stream and gives no way to drop them, and the certificate rotation
/// (design D4) has to close the listener, serve again with the new
/// certificate and drop the connections that still use the old one. The
/// listener also works on raw sockets: a handshake that stalls can only be
/// ended from a socket the TLS layer has not detached, which
/// `SecureServerSocket` and `SecureSocket.secureServer` do not allow.
class SecureListener {
  SecureListener._(this._server, this._socket, this._context, this.limits);

  final YaguraGrpcServer _server;
  final RawServerSocket _socket;
  final SecurityContext _context;
  final ListenerLimits limits;
  final _sockets = <RawSocket>{};
  var _epoch = 0;

  int get port => _socket.port;

  static Future<SecureListener> bind(
    YaguraGrpcServer server,
    InternetAddress address,
    int port,
    SecurityContext context, {
    ListenerLimits limits = const ListenerLimits(),
  }) async {
    final socket = await RawServerSocket.bind(address, port);
    final listener = SecureListener._(server, socket, context, limits);
    socket.listen(listener._accept, onError: (Object _) {});
    return listener;
  }

  void _accept(RawSocket raw) {
    if (_sockets.length >= limits.maxConnections) {
      raw.close();
      return;
    }
    _sockets.add(raw);
    unawaited(_handshake(raw, _epoch));
  }

  Future<void> _handshake(RawSocket raw, int epoch) async {
    final RawSecureSocket socket;
    try {
      raw.setOption(SocketOption.tcpNoDelay, true);
      socket = await RawSecureSocket.secureServer(
        raw,
        _context,
        requestClientCertificate: true,
      ).timeout(limits.handshakeTimeout);
    } on Object {
      // A client that fails the handshake (another CA, an expired
      // certificate), is too slow or leaves is not an error of the listener.
      _sockets.remove(raw);
      raw.close();
      return;
    }
    if (epoch != _epoch) {
      // Dropped during the handshake.
      _sockets.remove(raw);
      socket.close();
      return;
    }
    InternetAddress? remote;
    try {
      remote = socket.remoteAddress;
    } on Object {
      // The peer is already gone.
    }
    final certificate = socket.peerCertificate;
    final pipe = _SocketPipe(socket);
    unawaited(pipe.done.then<void>((_) => _sockets.remove(raw)));
    if (certificate == null) {
      // Pairing only: a connection that goes quiet is closed.
      Timer? idle;
      void arm() {
        idle?.cancel();
        idle = Timer(limits.idleTimeout, pipe.destroy);
      }

      arm();
      pipe.onActivity = arm;
      unawaited(pipe.done.then<void>((_) => idle?.cancel()));
    }
    unawaited(
      _server.serveConnection(
        connection: ServerTransportConnection.viaStreams(
          pipe.incoming,
          pipe.outgoing,
        ),
        clientCertificate: certificate,
        remoteAddress: remote,
      ),
    );
  }

  /// Stops accepting. With [dropConnections] the open connections end too;
  /// their clients reconnect.
  Future<void> close({bool dropConnections = false}) async {
    await _socket.close();
    if (dropConnections) {
      _epoch++;
      // The socket, not the HTTP/2 connection: terminating the connection
      // asserts in package:http2 while streams still hold queued messages.
      for (final socket in [..._sockets]) {
        socket.close();
      }
      _sockets.clear();
    }
  }
}

/// A [RawSocket] as the pair of streams that package:http2 reads and writes.
class _SocketPipe {
  _SocketPipe(this._socket) {
    _incoming = StreamController<List<int>>(
      onPause: () => _socket.readEventsEnabled = false,
      onResume: () => _socket.readEventsEnabled = true,
    );
    _outgoing = StreamController<List<int>>();
    _subscription = _socket.listen(
      _event,
      onError: (Object _) => destroy(),
      onDone: _finish,
    );
    unawaited(_pump());
  }

  final RawSocket _socket;
  late final StreamController<List<int>> _incoming;
  late final StreamController<List<int>> _outgoing;
  late final StreamSubscription<RawSocketEvent> _subscription;
  final _done = Completer<void>();
  Completer<void>? _writable;

  /// Called for every chunk read.
  void Function()? onActivity;

  Stream<List<int>> get incoming => _incoming.stream;
  StreamSink<List<int>> get outgoing => _PipeSink(this);
  Future<void> get done => _done.future;

  void _event(RawSocketEvent event) {
    switch (event) {
      case RawSocketEvent.read:
        while (true) {
          final data = _socket.read();
          if (data == null || data.isEmpty) break;
          onActivity?.call();
          if (!_incoming.isClosed) _incoming.add(data);
        }
      case RawSocketEvent.write:
        _writable?.complete();
        _writable = null;
      case RawSocketEvent.readClosed:
        if (!_incoming.isClosed) unawaited(_incoming.close());
      case RawSocketEvent.closed:
        _finish();
    }
  }

  Future<void> _pump() async {
    try {
      await for (final chunk in _outgoing.stream) {
        var offset = 0;
        while (offset < chunk.length) {
          final written = _socket.write(chunk, offset);
          offset += written;
          if (offset < chunk.length) {
            final ready = _writable = Completer<void>();
            _socket.writeEventsEnabled = true;
            await Future.any([ready.future, _done.future]);
            if (_done.isCompleted) return;
          }
        }
      }
      _socket.shutdown(SocketDirection.send);
    } on Object {
      destroy();
    }
  }

  /// Ends the connection at once.
  void destroy() {
    _socket.close();
    _finish();
  }

  void _finish() {
    if (!_incoming.isClosed) unawaited(_incoming.close());
    if (!_done.isCompleted) {
      _done.complete();
      unawaited(_subscription.cancel());
    }
    if (!_outgoing.isClosed) unawaited(_outgoing.close());
  }
}

/// The write side of a [_SocketPipe]: writes after the connection ended are
/// dropped instead of failing, as a closed socket would drop them.
class _PipeSink implements StreamSink<List<int>> {
  _PipeSink(this._pipe);

  final _SocketPipe _pipe;

  @override
  void add(List<int> data) {
    if (!_pipe._outgoing.isClosed) _pipe._outgoing.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.forEach(add);

  @override
  Future<void> close() {
    if (!_pipe._outgoing.isClosed) unawaited(_pipe._outgoing.close());
    return _pipe.done;
  }

  @override
  Future<void> get done => _pipe.done;
}
