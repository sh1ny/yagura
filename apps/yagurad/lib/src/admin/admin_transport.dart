import 'dart:typed_data';

/// One framed, duplex connection of the admin channel.
abstract interface class AdminConnection {
  /// Reads one message; fails `message_too_large` or `admin_request_timeout`.
  Future<Uint8List> readMessage({required Duration timeout});

  Future<void> writeMessage(Uint8List payload);

  Future<void> close();
}

/// The server end: the endpoint clients connect to.
abstract interface class AdminListener {
  /// Opens the endpoint; fails `admin_channel_squatted` when another process
  /// serves the name.
  Future<void> open();

  Stream<AdminConnection> get connections;

  Future<void> close();
}

/// The client end: opens a trusted connection or fails with the reason the
/// CLI prints (`daemon_not_running`, `access_denied`, `elevation_required`,
/// `admin_channel_untrusted`).
abstract interface class AdminConnector {
  Future<AdminConnection> connect();
}
