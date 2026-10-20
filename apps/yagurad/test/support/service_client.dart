import 'dart:io';
import 'dart:typed_data';

import 'package:grpc/grpc.dart';
// The tests build the channel from the rig's port.
// ignore: implementation_imports
import 'package:grpc/src/client/channel.dart' show ClientChannelBase;
import 'package:test/test.dart';
import 'package:yagura_pki/yagura_pki.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import 'elevated_support.dart';
import 'secure_support.dart';
import 'service_rig.dart';

final _code = RegExp(r'code=([0-9A-Z]{10})');

/// A paired device talking to the installed service of a [ServiceRig] over
/// mutual TLS (what the desktop client does), for the `elevated` rows that
/// need Install, Start and Stop.
class ServiceClient {
  ServiceClient._(this.channel);

  final ClientChannelBase channel;

  late final pb.InstancesClient instances = pb.InstancesClient(channel);
  late final pb.OperationsClient operations = pb.OperationsClient(channel);

  /// Pairs a new device with the service: a code from `yagurad pair` (the
  /// admin pipe), the CA from `Pairing.Info`, then `Enroll`.
  static Future<ServiceClient> pair(ServiceRig rig) async {
    final issued = await runCommand(rig.bundleExecutable, [
      'pair',
    ], timeout: const Duration(seconds: 30));
    expect(issued.exitCode, 0, reason: '${issued.stdout}${issued.stderr}');
    final code = _code.firstMatch('${issued.stdout}')?[1];
    expect(code, isNotNull, reason: 'no pairing code in ${issued.stdout}');

    final info = await pb.PairingClient(untrustedChannelTo(rig.port))
        .info(pb.PairingInfoRequest());
    final caPem = certificatePem(info.caCertificateDer);
    final key = generateKeyPair();
    final enrolling = ClientChannel(
      InternetAddress.loopbackIPv4.address,
      port: rig.port,
      options: ChannelOptions(
        // The server certificate names `localhost` as well as its own id.
        credentials: MutualTlsCredentials(caPem: caPem, authority: 'localhost'),
        connectTimeout: const Duration(seconds: 10),
      ),
    );
    addTearDown(enrolling.terminate);
    final enrolled = await pb.PairingClient(enrolling).enroll(
      pb.EnrollRequest(
        code: code!,
        deviceName: 'elevated-test',
        csrDer: buildCsr(key: key, commonName: 'elevated-test'),
      ),
    );
    final channel = ClientChannel(
      InternetAddress.loopbackIPv4.address,
      port: rig.port,
      options: ChannelOptions(
        credentials: MutualTlsCredentials(
          caPem: caPem,
          authority: 'localhost',
          certificate: Uint8List.fromList(enrolled.clientCertificateDer),
          key: key,
        ),
        connectTimeout: const Duration(seconds: 10),
      ),
    );
    addTearDown(channel.terminate);
    return ServiceClient._(channel);
  }

  /// Waits for [started] to end and fails unless it succeeded.
  Future<pb.Operation> succeeded(
    pb.Operation started, {
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final op = await ended(started, timeout: timeout);
    if (op.status != pb.OperationStatus.OPERATION_STATUS_SUCCEEDED) {
      fail(
        'operation ${op.id} ended ${op.status.name}: ${op.resultReason} '
        '${op.resultMessage}',
      );
    }
    return op;
  }

  /// Waits for [started] to end, however it ends.
  Future<pb.Operation> ended(
    pb.Operation started, {
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var op = started;
    while (true) {
      switch (op.status) {
        case pb.OperationStatus.OPERATION_STATUS_SUCCEEDED ||
            pb.OperationStatus.OPERATION_STATUS_FAILED ||
            pb.OperationStatus.OPERATION_STATUS_CANCELLED ||
            pb.OperationStatus.OPERATION_STATUS_INTERRUPTED:
          return op;
        default:
      }
      if (DateTime.now().isAfter(deadline)) {
        fail('operation ${op.id} still ${op.status.name} after $timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      op = await operations.getOperation(
        pb.GetOperationRequest(operationId: op.id),
      );
    }
  }
}
