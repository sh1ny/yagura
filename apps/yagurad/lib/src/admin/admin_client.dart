import 'admin_transport.dart';
import 'admin_wire.dart';
import '../errors.dart';

/// The CLI's side: opens a trusted connection, sends one request and returns
/// the result, or throws the reason the daemon (or the connection) gave.
class AdminClient {
  AdminClient(this._connector, {this.readTimeout = adminReadTimeout});

  final AdminConnector _connector;
  final Duration readTimeout;

  Future<Map<String, Object?>> call(
    String command, [
    Map<String, Object?> args = const {},
  ]) async {
    final payload = encodeRequest(AdminRequest(command, args));
    final connection = await _connector.connect();
    try {
      await connection.writeMessage(payload);
      final reply = decodeReply(
        await connection.readMessage(timeout: readTimeout),
      );
      if (reply.isOk) return reply.result;
      throw YaguraException(
        reply.reason,
        reply.message,
        details: reply.details,
      );
    } finally {
      await connection.close();
    }
  }
}
