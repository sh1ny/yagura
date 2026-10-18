import 'dart:async';
import 'dart:io';

import 'package:http2/transport.dart';

import '../security/address_key.dart';
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
    this.maxUnauthenticated = 64,
    this.maxPerAddress = 8,
    this.maxDevices = 256,
    this.handshakeTimeout = const Duration(seconds: 10),
    this.noCertificateLifetime = const Duration(seconds: 30),
  });

  /// Connections that have not presented a client certificate, handshaking
  /// or not. At the bound the oldest of them makes room for a new one.
  final int maxUnauthenticated;

  /// Unauthenticated connections from one remote address (IPv6 per /64); a
  /// further one from that address is closed at accept.
  final int maxPerAddress;

  /// Connections that presented a valid client certificate; beyond it the
  /// newest is closed. Separate from the unauthenticated pool, so a host
  /// without a certificate cannot take a device's place.
  final int maxDevices;

  /// From accept to the end of the TLS handshake.
  final Duration handshakeTimeout;

  /// How long a connection without a client certificate lives, counted from
  /// accept. A hard lifetime, not an idle timer: no byte and no HTTP/2 PING
  /// extends it. Pairing needs a few round trips.
  final Duration noCertificateLifetime;
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

  // Insertion order is accept order: the first entry is the oldest.
  final _unauthenticated = <_Connection>{};
  final _perAddress = <String, int>{};
  final _devices = <_Connection>{};
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
    String key;
    try {
      key = addressKey(raw.remoteAddress);
    } on Object {
      raw.close();
      return;
    }
    // One host cannot hold more than its share, whatever else is open.
    if ((_perAddress[key] ?? 0) >= limits.maxPerAddress) {
      raw.close();
      return;
    }
    if (_unauthenticated.length >= limits.maxUnauthenticated) {
      // The pool is full: the oldest connection without a certificate makes
      // room (one that finished its handshake first, since it is only
      // waiting), so a device connecting now is not refused because of them.
      final victim =
          _unauthenticated.where((c) => c.handshaken).firstOrNull ??
          _unauthenticated.first;
      victim.drop();
    }
    final connection = _Connection(raw, key);
    _unauthenticated.add(connection);
    _perAddress[key] = (_perAddress[key] ?? 0) + 1;
    connection.release = () => _release(connection);
    // A hard lifetime from accept for every connection until it presents a
    // certificate; the handshake has its own, shorter, deadline.
    connection.lifetime = Timer(limits.noCertificateLifetime, connection.drop);
    unawaited(_handshake(connection, _epoch));
  }

  void _release(_Connection connection) {
    if (_unauthenticated.remove(connection)) {
      final left = (_perAddress[connection.key] ?? 1) - 1;
      if (left <= 0) {
        _perAddress.remove(connection.key);
      } else {
        _perAddress[connection.key] = left;
      }
    }
    _devices.remove(connection);
  }

  Future<void> _handshake(_Connection connection, int epoch) async {
    final raw = connection.raw;
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
      connection.drop();
      return;
    }
    if (epoch != _epoch || connection.dropped) {
      // Dropped during the handshake.
      connection.dropped = true;
      socket.close();
      connection.drop();
      return;
    }
    connection
      ..handshaken = true
      ..secure = socket;
    InternetAddress? remote;
    try {
      remote = socket.remoteAddress;
    } on Object {
      // The peer is already gone.
    }
    final certificate = socket.peerCertificate;
    if (certificate != null) {
      // A device: out of the unauthenticated pool, into its own.
      if (_devices.length >= limits.maxDevices) {
        connection.drop();
        return;
      }
      connection.lifetime?.cancel();
      _release(connection);
      _devices.add(connection);
    }
    final pipe = _SocketPipe(socket);
    connection.pipe = pipe;
    unawaited(pipe.done.then<void>((_) => connection.drop()));
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
      for (final connection in [..._unauthenticated, ..._devices]) {
        connection.drop();
      }
    }
  }
}

/// One accepted connection and what the listener needs to end it.
class _Connection {
  _Connection(this.raw, this.key);

  final RawSocket raw;

  /// The remote address as counted by the limits.
  final String key;
  RawSecureSocket? secure;
  _SocketPipe? pipe;
  Timer? lifetime;
  void Function()? release;
  var handshaken = false;
  var dropped = false;

  /// Ends the connection at once and frees its slot.
  void drop() {
    dropped = true;
    lifetime?.cancel();
    release?.call();
    if (pipe case final pipe?) {
      pipe.destroy();
    } else {
      (secure ?? raw).close();
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
