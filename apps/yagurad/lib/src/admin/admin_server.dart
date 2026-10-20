import 'dart:async';

import '../errors.dart';
import 'admin_transport.dart';
import 'admin_wire.dart';

typedef AdminHandler = Future<Map<String, Object?>> Function(
  AdminRequest request,
);

/// Serves the admin channel: one request and one reply per connection.
class AdminServer {
  AdminServer(
    this._listener,
    this._handler, {
    this.readTimeout = adminReadTimeout,
  });

  final AdminListener _listener;
  final AdminHandler _handler;
  final Duration readTimeout;

  StreamSubscription<AdminConnection>? _subscription;
  final _inFlight = <Future<void>>{};
  var _serving = false;

  /// Whether the server is open and its endpoint can take a client.
  bool get serving => _serving && _listener.healthy;

  /// Opens the endpoint; `admin_channel_squatted` when another process
  /// serves it.
  Future<void> start() async {
    await _listener.open();
    _serving = true;
    _subscription = _listener.connections.listen((connection) {
      late final Future<void> done;
      done = _serve(connection).whenComplete(() => _inFlight.remove(done));
      _inFlight.add(done);
    });
  }

  Future<void> _serve(AdminConnection connection) async {
    try {
      final AdminReply reply;
      try {
        final request = decodeRequest(
          await connection.readMessage(timeout: readTimeout),
        );
        reply = AdminReply.ok(await _handler(request));
      } on YaguraException catch (e) {
        await _send(
          connection,
          AdminReply.error(e.reason, e.message, details: e.details),
        );
        return;
      } on Object {
        await _send(
          connection,
          AdminReply.error('internal_error', 'the command failed'),
        );
        return;
      }
      await _send(connection, reply);
    } finally {
      await connection.close();
    }
  }

  Future<void> _send(AdminConnection connection, AdminReply reply) async {
    try {
      await connection.writeMessage(encodeReply(reply));
    } on Object {
      // The client is gone; there is nobody to tell.
    }
  }

  /// Stops accepting, waits for the requests being served and frees the
  /// endpoint.
  Future<void> close() async {
    if (!_serving) return;
    _serving = false;
    await _listener.close();
    await _subscription?.cancel();
    await Future.wait([..._inFlight]);
  }
}
