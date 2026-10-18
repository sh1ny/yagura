import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/api/api_server.dart';
import 'package:yagurad/src/api/secure_listener.dart';

import '../support/daemon_support.dart';
import '../support/secure_support.dart';

/// A secure harness whose listener has [limits].
Future<SecureHarness> start(ListenerLimits limits) => SecureHarness.start(
  TestEnv(),
  serve: (daemon, lines) => ApiServer.serveSecure(
    daemon,
    address: InternetAddress.loopbackIPv4,
    port: 0,
    logSink: lines.add,
    binder: (server, address, port, context) =>
        SecureListener.bind(server, address, port, context, limits: limits),
  ),
);

/// Completes when the peer ends or resets [socket].
Future<void> closedWithin(Socket socket, Duration limit) {
  final done = Completer<void>();
  socket.listen(
    (_) {},
    onDone: done.complete,
    onError: (Object _) {
      if (!done.isCompleted) done.complete();
    },
    cancelOnError: true,
  );
  return done.future.timeout(limit);
}

void main() {
  test('connections beyond the cap are closed at once', () async {
    final h = await start(
      const ListenerLimits(
        maxConnections: 3,
        handshakeTimeout: Duration(seconds: 30),
      ),
    );
    final held = <Socket>[];
    for (var i = 0; i < 3; i++) {
      held.add(
        await Socket.connect(InternetAddress.loopbackIPv4, h.server.port),
      );
    }
    // Let the listener accept them all before the next one arrives.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final extra = await Socket.connect(
      InternetAddress.loopbackIPv4,
      h.server.port,
    );

    await closedWithin(extra, const Duration(seconds: 3));
    for (final socket in held) {
      socket.destroy();
    }
    // A slot is free again and a real client gets through.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final info = await pb.PairingClient(h.channelWith())
        .info(pb.PairingInfoRequest());
    expect(info.caCertificateDer, isNotEmpty);
  });

  test('a connection that never finishes the handshake is closed', () async {
    final h = await start(
      const ListenerLimits(handshakeTimeout: Duration(milliseconds: 400)),
    );
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      h.server.port,
    );

    await closedWithin(socket, const Duration(seconds: 5));
  });

  test('a connection without a certificate is closed when idle', () async {
    final h = await start(
      const ListenerLimits(idleTimeout: Duration(milliseconds: 600)),
    );
    final plain = await Socket.connect(
      InternetAddress.loopbackIPv4,
      h.server.port,
    );
    final secure = await SecureSocket.secure(
      plain,
      host: h.authority,
      context: SecurityContext()
        ..setTrustedCertificatesBytes(utf8.encode(h.caPem)),
      supportedProtocols: ['h2'],
    );

    await closedWithin(secure, const Duration(seconds: 5));
  });

  test('a paired device keeps its connection past the idle limit', () async {
    final h = await start(
      const ListenerLimits(idleTimeout: Duration(milliseconds: 600)),
    );
    final device = await h.pair('desk-01');
    final system = device.system;
    await system.getInfo(pb.GetInfoRequest());

    await Future<void>.delayed(const Duration(seconds: 2));

    expect((await system.getInfo(pb.GetInfoRequest())).devMode, isFalse);
  });
}
