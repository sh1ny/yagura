import 'dart:convert';
import 'dart:typed_data';

import '../errors.dart';

/// The version of the admin channel protocol (`admin_api: 1`).
const adminApi = 1;

/// The name of the admin pipe.
const adminPipeName = r'\\.\pipe\yagurad-admin';

/// The pipe's descriptor: SYSTEM and Administrators only (design D5).
const adminPipeSddl = 'D:P(A;;GA;;;SY)(A;;GA;;;BA)';

/// Bytes in one message, in either direction.
const maxAdminMessage = 64 * 1024;

/// How long the server waits for a request to arrive.
const adminReadTimeout = Duration(seconds: 5);

/// Clients served at once.
const maxAdminClients = 4;

class AdminRequest {
  AdminRequest(this.command, [this.args = const {}]);

  final String command;
  final Map<String, Object?> args;
}

class AdminReply {
  AdminReply.ok(this.result) : reason = '', message = '', details = const {};
  AdminReply.error(this.reason, this.message, {this.details = const {}})
    : result = const {};

  final Map<String, Object?> result;
  final String reason;
  final String message;
  final Map<String, Object?> details;

  bool get isOk => reason.isEmpty;
}

Uint8List _encode(Map<String, Object?> message) {
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(message)));
  if (bytes.length > maxAdminMessage) {
    throw YaguraException(
      'message_too_large',
      'an admin message is at most $maxAdminMessage bytes',
      details: {'limit': maxAdminMessage},
    );
  }
  return bytes;
}

Map<String, Object?> _object(Uint8List payload, String reason, String what) {
  try {
    final decoded = jsonDecode(utf8.decode(payload));
    if (decoded is Map<String, Object?>) return decoded;
  } on FormatException {
    // Falls through to the refusal.
  }
  throw YaguraException(reason, 'the $what is not a JSON object');
}

Uint8List encodeRequest(AdminRequest request) => _encode({
  'admin_api': adminApi,
  'command': request.command,
  'args': request.args,
});

AdminRequest decodeRequest(Uint8List payload) {
  final json = _object(payload, 'admin_request_invalid', 'request');
  if (json['admin_api'] != adminApi) {
    throw YaguraException(
      'admin_api_unsupported',
      'this daemon speaks admin_api $adminApi, not ${json['admin_api']}',
      details: {'supported': adminApi},
    );
  }
  final command = json['command'];
  final args = json['args'] ?? const <String, Object?>{};
  if (command is! String || command.isEmpty || args is! Map<String, Object?>) {
    throw YaguraException(
      'admin_request_invalid',
      'a request needs a command and an object of arguments',
    );
  }
  return AdminRequest(command, args);
}

Uint8List encodeReply(AdminReply reply) => _encode({
  'admin_api': adminApi,
  if (reply.isOk) ...{
    'ok': true,
    'result': reply.result,
  } else ...{
    'ok': false,
    'reason': reply.reason,
    'message': reply.message,
    'details': reply.details,
  },
});

AdminReply decodeReply(Uint8List payload) {
  final json = _object(payload, 'admin_reply_invalid', 'reply');
  if (json['ok'] == true && json['result'] is Map<String, Object?>) {
    return AdminReply.ok(json['result']! as Map<String, Object?>);
  }
  final reason = json['reason'];
  if (json['ok'] == false && reason is String && reason.isNotEmpty) {
    final details = json['details'];
    return AdminReply.error(
      reason,
      json['message'] is String ? json['message']! as String : '',
      details: details is Map<String, Object?> ? details : const {},
    );
  }
  throw YaguraException(
    'admin_reply_invalid',
    'the admin channel sent a reply that is neither a result nor a reason',
  );
}
