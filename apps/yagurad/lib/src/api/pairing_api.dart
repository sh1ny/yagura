import 'dart:io';
import 'dart:typed_data';

import 'package:grpc/grpc.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../errors.dart';
import '../host/daemon.dart';
import '../security/devices.dart';
import '../security/pairing.dart';
import '../security/security.dart';
import '../version.dart';
import 'convert.dart';
import 'service_support.dart';

/// The `Pairing` service of a service-mode daemon (design D1, D4).
class PairingApi extends pb.PairingServiceBase with GuardedService {
  PairingApi(this.daemon, this.security, this.logSink);

  final Daemon daemon;
  final DaemonSecurity security;

  @override
  final LogSink logSink;

  @override
  Future<pb.PairingInfo> info(
    ServiceCall call,
    pb.PairingInfoRequest request,
  ) async => pb.PairingInfo(
    daemonName: Platform.localHostname,
    caFingerprintSha256: security.identity.caFingerprint,
    apiVersion: apiVersions.last,
    caCertificateDer: security.identity.caCertificate.der,
    tlsAuthority: security.identity.authority,
  );

  @override
  Future<pb.EnrollResponse> enroll(
    ServiceCall call,
    pb.EnrollRequest request,
  ) async {
    try {
      return security.pairing.enroll(
        code: request.code,
        deviceName: request.deviceName,
        csrDer: Uint8List.fromList(request.csrDer),
        address: call.remoteAddress,
      );
    } on YaguraException catch (e) {
      // A wrong code is an authentication failure: it is counted per address
      // like the calls the gate refuses.
      if (e.reason == 'pairing_code_invalid' ||
          e.reason == 'pairing_throttled') {
        security.failures.record(
          call.remoteAddress ?? InternetAddress.anyIPv4,
          e.reason,
        );
      }
      rethrow;
    }
  }

  @override
  Future<pb.ListDevicesResponse> listDevices(
    ServiceCall call,
    pb.ListDevicesRequest request,
  ) async {
    final caller = security.gate.callerOf(call);
    return pb.ListDevicesResponse(
      devices: [
        for (final device in security.devices.list())
          _toPb(device, device.id == caller),
      ],
    );
  }

  @override
  Future<pb.Device> revokeDevice(
    ServiceCall call,
    pb.RevokeDeviceRequest request,
  ) async {
    final caller = security.gate.callerOf(call)!;
    final target = security.devices.get(request.deviceId);
    if (target == null) {
      throw YaguraException(
        'device_not_found',
        'no device has the id ${request.deviceId}',
        details: {'deviceId': request.deviceId},
      );
    }
    if (target.id == caller && security.devices.activeCount <= 1) {
      throw YaguraException(
        'last_device',
        'this is the only enrolled device; revoke it on the host with '
            '`yagurad devices revoke`, or pair another device first',
      );
    }
    final revoked = security.revokeDevice(
      target.id,
      caller,
      except: security.gate.permitOf(call),
    );
    return _toPb(revoked, revoked.id == caller);
  }

  @override
  Future<pb.Device> renameDevice(
    ServiceCall call,
    pb.RenameDeviceRequest request,
  ) async {
    final caller = security.gate.callerOf(call);
    final name = checkDeviceName(request.name);
    final device = security.devices.rename(request.deviceId, name);
    return _toPb(device, device.id == caller);
  }

  @override
  Future<pb.EnrollResponse> renewCertificate(
    ServiceCall call,
    pb.RenewCertificateRequest request,
  ) async => security.pairing.renew(
    deviceId: security.gate.callerOf(call)!,
    csrDer: Uint8List.fromList(request.csrDer),
  );

  pb.Device _toPb(DeviceRecord device, bool isCaller) => pb.Device(
    id: device.id,
    name: device.name,
    certificates: [
      for (final c in device.certificates)
        pb.DeviceCertificate(sha256: c.sha256, notAfter: timestamp(c.notAfter)),
    ],
    enrolledAt: timestamp(device.enrolledAt),
    lastSeenAt: device.lastSeenAt == null
        ? null
        : timestamp(device.lastSeenAt!),
    lastAddress: device.lastAddress,
    certificateExpiresAt: device.certificateExpiresAt == null
        ? null
        : timestamp(device.certificateExpiresAt!),
    revoked: device.revoked,
    revokedAt: device.revokedAt == null ? null : timestamp(device.revokedAt!),
    revokedByDeviceId: device.revokedBy,
    isCaller: isCaller,
  );
}
