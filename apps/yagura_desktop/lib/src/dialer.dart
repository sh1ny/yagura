/// How the client opens connections to daemons (design D13).
///
/// The seam sits above the sockets: production uses [GrpcDialer], widget tests
/// inject a fake that hands out fake daemons.
library;

import 'dart:typed_data';

import 'package:yagura_proto/yagura_proto.dart';

import 'credentials.dart';
import 'grpc_transport.dart';
import 'transport.dart';

/// The two `Pairing` calls that work without a client certificate.
abstract interface class PairingChannel {
  Future<PairingInfo> info();
  Future<EnrollResponse> enroll(EnrollRequest request);
  Future<void> close();
}

abstract interface class DaemonDialer {
  /// A mutual-TLS transport: [credentials].caDer is the only trusted root,
  /// the server is checked against [authority] (`yagurad-<daemon-id>`), and
  /// the address used does not matter.
  DaemonTransport secure({
    required String host,
    required int port,
    required String authority,
    required DeviceCredentials credentials,
  });

  /// The plaintext development transport; [host] must be a loopback address.
  DaemonTransport development({required String host, required int port});

  /// A channel for `Pairing.Info` and `Pairing.Enroll`. Without [pinnedCa] the
  /// server certificate is not verified (the CA is not known yet; the caller
  /// checks its fingerprint against the pairing string); with it, the CA is
  /// the only trusted root and the server is checked against [authority].
  PairingChannel pairing({
    required String host,
    required int port,
    Uint8List? pinnedCa,
    String? authority,
  });
}

/// [DaemonDialer] over gRPC.
final class GrpcDialer implements DaemonDialer {
  const GrpcDialer();

  @override
  DaemonTransport secure({
    required String host,
    required int port,
    required String authority,
    required DeviceCredentials credentials,
  }) => GrpcTransport.secure(
    host: host,
    port: port,
    authority: authority,
    credentials: credentials,
  );

  @override
  DaemonTransport development({required String host, required int port}) =>
      GrpcTransport(host: host, port: port);

  @override
  PairingChannel pairing({
    required String host,
    required int port,
    Uint8List? pinnedCa,
    String? authority,
  }) => GrpcPairingChannel(
    host: host,
    port: port,
    pinnedCa: pinnedCa,
    authority: authority,
  );
}
