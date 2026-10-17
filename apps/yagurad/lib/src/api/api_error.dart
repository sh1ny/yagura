import 'dart:convert';
import 'dart:math';

import 'package:grpc/grpc.dart';
import 'package:protobuf/protobuf.dart' show CodedBufferWriter, PbFieldType;
import 'package:protobuf/well_known_types/google/protobuf/any.pb.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../errors.dart';

/// The gRPC status code of a reason (`docs/protocol.md`, Errors). A reason
/// the table does not name is a failed precondition: the request was fine
/// but the daemon is not in a state that allows it.
int statusCodeFor(String reason) => switch (reason) {
  'not_implemented' => StatusCode.unimplemented,
  'internal_error' => StatusCode.internal,
  'instance_not_found' ||
  'operation_not_found' ||
  'operation_expired' ||
  'snapshot_not_found' ||
  'plugin_missing' => StatusCode.notFound,
  'settings_invalid' ||
  'invalid_json' ||
  'confirmation_mismatch' ||
  'directory_not_allowed' => StatusCode.invalidArgument,
  'port_conflict' => StatusCode.alreadyExists,
  'queue_full' ||
  'too_many_subscribers' ||
  'message_too_large' => StatusCode.resourceExhausted,
  _ => StatusCode.failedPrecondition,
};

/// Turns [error] into the status of a failed call: a [GrpcError] carrying a
/// packed `yagura.v1.ErrorDetail` (`docs/protocol.md`, Errors).
///
/// A [YaguraException] keeps its reason and details. Anything else is a bug:
/// it becomes `INTERNAL` / `internal_error` with an incident id, and [log]
/// receives the incident id with the stack trace.
GrpcError toGrpcError(
  Object error,
  StackTrace stackTrace, {
  required String method,
  required void Function(String line) log,
}) {
  if (error is GrpcError &&
      (error.trailers?.containsKey(_detailsHeader) ?? false)) {
    return error;
  }
  if (error is YaguraException && error.reason != 'internal_error') {
    return _status(
      statusCodeFor(error.reason),
      pb.ErrorDetail(
        reason: error.reason,
        message: error.message,
        fieldViolations: _fieldViolations(error.details),
        metadata: _metadata(error.details).entries,
      ),
    );
  }
  if (error is GrpcError) {
    return _status(
      error.code,
      pb.ErrorDetail(
        reason: error.code == StatusCode.unimplemented
            ? 'not_implemented'
            : 'internal_error',
        message: error.message ?? error.codeName,
      ),
    );
  }
  final incident = newIncidentId();
  log('incident $incident: $method failed: $error\n$stackTrace');
  return _status(
    StatusCode.internal,
    pb.ErrorDetail(
      reason: 'internal_error',
      message: 'internal error; quote incident $incident to the administrator',
      incidentId: incident,
    ),
  );
}

/// A status with reason [reason] and message [message].
GrpcError grpcErrorFor(
  String reason,
  String message, {
  Map<String, String> metadata = const {},
}) => _status(
  statusCodeFor(reason),
  pb.ErrorDetail(reason: reason, message: message, metadata: metadata.entries),
);

final _random = Random.secure();

String newIncidentId() => [
  'inc-',
  for (var i = 0; i < 12; i++) _random.nextInt(16).toRadixString(16),
].join();

const _detailsHeader = 'grpc-status-details-bin';

GrpcError _status(int code, pb.ErrorDetail detail) {
  // package:grpc does not send GrpcError.details from a server, so the
  // google.rpc.Status carrying the detail goes out as the trailer itself.
  final status = CodedBufferWriter()
    ..writeField(1, PbFieldType.O3, code)
    ..writeField(2, PbFieldType.OS, detail.message)
    ..writeField(3, PbFieldType.OM, Any.pack(detail));
  return GrpcError.custom(
    code,
    detail.message,
    [Any.pack(detail)],
    null,
    {_detailsHeader: base64Url.encode(status.toBuffer()).replaceAll('=', '')},
  );
}

List<pb.FieldViolation> _fieldViolations(Map<String, Object?> details) => [
  if (details['fieldViolations'] case final List<Object?> violations)
    for (final violation in violations)
      if (violation is Map<String, Object?>)
        pb.FieldViolation(
          field_1: '${violation['field']}',
          description: '${violation['description']}',
        ),
];

Map<String, String> _metadata(Map<String, Object?> details) => {
  for (final MapEntry(:key, :value) in details.entries)
    if (key != 'fieldViolations' && key != 'stack' && value != null)
      _snakeCase(key): '$value',
};

String _snakeCase(String name) =>
    name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
