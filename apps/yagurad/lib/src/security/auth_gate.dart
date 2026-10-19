import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:protobuf/well_known_types/google/protobuf/any.pb.dart' show Any;
import 'package:yagura_pki/yagura_pki.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../api/api_error.dart';
import 'audit.dart';
import 'devices.dart';
import 'method_access.dart';

/// The decision of the gate for one call.
class CallPermit {
  CallPermit({
    this.deviceId,
    this.address = '',
    this.mutating = false,
    this.onRelease,
  });

  /// The enrolled device behind the call; null for an exempt call or in dev
  /// mode.
  final String? deviceId;

  /// The remote address as text.
  final String address;

  /// Whether the call is audited when it ends.
  final bool mutating;

  final void Function(CallPermit permit)? onRelease;

  /// Set by the call wrapper: ends the call because its device was revoked.
  void Function()? revoke;

  /// What the audit entry names as the target, taken from the first request
  /// message.
  String target = '';

  void release() => onRelease?.call(this);
}

/// Decides whether a call may run (design D2). Fail-closed: a method the
/// table does not classify needs an enrolled device.
abstract interface class AuthGate {
  /// Whether callers are authenticated; false only in dev mode.
  bool get authenticates;

  /// Returns the permit of the call, or throws the [GrpcError] it fails with.
  CallPermit authorize(ServiceCall call, String method);

  /// Records the end of a call that was audited.
  void finished(CallPermit permit, String method, String result);
}

/// Dev mode: every call is allowed and nothing is recorded.
class AllowAllGate implements AuthGate {
  const AllowAllGate();

  @override
  bool get authenticates => false;

  @override
  CallPermit authorize(ServiceCall call, String method) => CallPermit();

  @override
  void finished(CallPermit permit, String method, String result) {}
}

/// Mutual TLS: the presented certificate must belong to an enrolled device
/// that is not revoked and has not expired.
class DeviceAuthGate implements AuthGate {
  DeviceAuthGate({
    required this._devices,
    required this._failures,
    required this._audit,
    required this._clock,
  });

  final DeviceStore _devices;
  final AuthFailureLog _failures;
  final AuditLog _audit;
  final DateTime Function() _clock;

  final _active = <String, Set<CallPermit>>{};
  final _permits = Expando<CallPermit>('permit');

  @override
  bool get authenticates => true;

  @override
  CallPermit authorize(ServiceCall call, String method) {
    final access = methodAccess[method];
    final address = call.remoteAddress;
    final text = address?.address ?? '';
    if (access == MethodAccess.exempt) return CallPermit(address: text);

    final certificate = call.clientCertificate;
    if (certificate == null) {
      throw _refuse(
        address,
        'unauthenticated',
        'a client certificate is required',
      );
    }
    final entry = _devices.lookup(sha256Hex(certificate.der));
    if (entry == null) {
      throw _refuse(
        address,
        'unauthenticated',
        'this certificate belongs to no enrolled device',
      );
    }
    if (entry.revoked) {
      throw _refuse(address, 'device_revoked', 'this device was revoked');
    }
    // TLS reads the clock of this host; the gate reads the daemon's, and
    // checks the certificate's own end besides the device row.
    final now = _clock();
    if (!now.isBefore(entry.notAfter) ||
        !now.isBefore(certificate.endValidity.toUtc())) {
      throw _refuse(
        address,
        'certificate_expired',
        'this device certificate has expired; pair the device again',
      );
    }
    _devices
      ..markUsed(sha256Hex(certificate.der))
      ..seen(entry.deviceId, text);
    final permit = CallPermit(
      deviceId: entry.deviceId,
      address: text,
      mutating: access == MethodAccess.mutating,
      onRelease: (p) => _active[entry.deviceId]?.remove(p),
    );
    _active.putIfAbsent(entry.deviceId, () => {}).add(permit);
    _permits[call] = permit;
    return permit;
  }

  @override
  void finished(CallPermit permit, String method, String result) {
    if (!permit.mutating || permit.deviceId == null) return;
    _audit.record(
      deviceId: permit.deviceId!,
      address: permit.address,
      method: method,
      target: permit.target,
      result: result,
    );
  }

  /// The permit the gate gave [call], null when it was exempt.
  CallPermit? permitOf(ServiceCall call) => _permits[call];

  /// The device whose certificate [call] presented, null when it is not an
  /// enrolled device. Only meaningful after the gate allowed the call.
  String? callerOf(ServiceCall call) => _permits[call]?.deviceId;

  /// Ends every open call of [deviceId] except [except]; the device was
  /// revoked.
  void cancelCalls(String deviceId, {CallPermit? except}) {
    for (final permit in [...?_active[deviceId]]) {
      if (permit != except) permit.revoke?.call();
    }
  }

  GrpcError _refuse(InternetAddress? address, String reason, String message) {
    _failures.record(address ?? InternetAddress.anyIPv4, reason);
    return grpcErrorFor(reason, message);
  }
}

/// The reason of the `ErrorDetail` a failed call carries.
String reasonOfError(Object error) {
  if (error is GrpcError) {
    for (final detail in error.details ?? const []) {
      if (detail is Any && detail.typeUrl.endsWith('/yagura.v1.ErrorDetail')) {
        return pb.ErrorDetail.fromBuffer(detail.value).reason;
      }
    }
    return error.codeName.toLowerCase();
  }
  return 'internal_error';
}

/// What the audit entry names as the target of a call: the instance, the
/// device or the setting, never a value.
String auditTarget(Object? request) {
  switch (request) {
    case pb.SetSecretRequest():
      return '${request.instanceId} ${request.key}';
    case pb.DeleteSecretRequest():
      return '${request.instanceId} ${request.key}';
    case pb.LifecycleRequest():
      return request.skipSnapshot
          ? '${request.instanceId} skip_snapshot'
          : request.instanceId;
    case pb.CreateInstanceRequest():
      return '${request.pluginId} ${request.name}';
  }
  // Only the names of the fields below are read, so a value that arrives in
  // another field (a secret, a password) can never reach the audit log.
  final json = request is GeneratedMessage ? request.toProto3Json() : null;
  if (json is Map) {
    for (final field in const [
      'instanceId',
      'deviceId',
      'operationId',
      'accountId',
      'id',
    ]) {
      final value = json[field];
      if (value is String && value.isNotEmpty) return value;
    }
  }
  return '';
}
