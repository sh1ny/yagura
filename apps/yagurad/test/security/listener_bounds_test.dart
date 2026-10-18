import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:grpc/grpc.dart';
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/api/api_server.dart';
import 'package:yagurad/src/api/secure_listener.dart';
import 'package:yagurad/src/security/address_key.dart';

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

/// A plain TCP connection to the daemon from the loopback address [from].
Future<Socket> connectFrom(SecureHarness h, String from) => Socket.connect(
  InternetAddress.loopbackIPv4,
  h.server.port,
  sourceAddress: InternetAddress(from),
);

/// Whether the peer ends or resets [socket] within [limit].
Future<bool> closesWithin(Socket socket, Duration limit) {
  final done = Completer<bool>();
  socket.listen(
    (_) {},
    onDone: () {
      if (!done.isCompleted) done.complete(true);
    },
    onError: (Object _) {
      if (!done.isCompleted) done.complete(true);
    },
    cancelOnError: true,
  );
  return done.future.timeout(limit, onTimeout: () => false);
}

/// A TLS connection with HTTP/2 negotiated and no client certificate.
Future<SecureSocket> tlsWithoutCertificate(SecureHarness h) async {
  final plain = await Socket.connect(
    InternetAddress.loopbackIPv4,
    h.server.port,
  );
  return SecureSocket.secure(
    plain,
    host: h.authority,
    context: SecurityContext()
      ..setTrustedCertificatesBytes(utf8.encode(h.caPem)),
    supportedProtocols: ['h2'],
  );
}

void main() {
  test('one address cannot hold more than 8 connections', () async {
    final h = await start(
      const ListenerLimits(handshakeTimeout: Duration(seconds: 30)),
    );
    final sockets = <Socket>[];
    for (var i = 0; i < 12; i++) {
      sockets.add(await connectFrom(h, '127.0.0.2'));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final closed = [
      for (final s in sockets)
        await closesWithin(s, const Duration(milliseconds: 300)),
    ];

    expect(closed.where((c) => c), hasLength(4), reason: 'the 9th to 12th');
    expect(closed.take(8), everyElement(isFalse));
    // Another address is not affected.
    final other = await connectFrom(h, '127.0.0.3');
    expect(
      await closesWithin(other, const Duration(milliseconds: 500)),
      isFalse,
    );
    for (final s in [...sockets, other]) {
      s.destroy();
    }
  });

  test(
    'a device connects while 64 unauthenticated connections are held',
    () async {
      final h = await start(
        const ListenerLimits(handshakeTimeout: Duration(seconds: 30)),
      );
      final device = await h.pair('desk-01');
      final held = <Socket>[];
      for (var host = 1; host <= 8; host++) {
        for (var i = 0; i < 8; i++) {
          held.add(await connectFrom(h, '127.0.1.$host'));
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // The pool is full: a new connection makes room, a device is served.
      final info = await device.system.getInfo(pb.GetInfoRequest());
      expect(info.devMode, isFalse);
      // The attackers did not get more than their share.
      final ninth = await connectFrom(h, '127.0.1.8');
      expect(await closesWithin(ninth, const Duration(seconds: 1)), isTrue);
      ninth.destroy();
      for (final s in held) {
        s.destroy();
      }
    },
  );

  test(
    'devices are bounded separately from the unauthenticated pool',
    () async {
      final h = await start(const ListenerLimits(maxDevices: 2));
      final a = await h.pair('desk-01');
      final b = await h.pair('desk-02');
      final c = await h.pair('desk-03');
      await a.system.getInfo(pb.GetInfoRequest());
      await b.system.getInfo(pb.GetInfoRequest());

      // The newest connection is the one refused.
      await expectLater(
        c.system.getInfo(
          pb.GetInfoRequest(),
          options: CallOptions(timeout: const Duration(seconds: 3)),
        ),
        throwsA(anything),
      );
      await a.system.getInfo(pb.GetInfoRequest());
    },
  );

  test('a connection that never finishes the handshake is closed', () async {
    final h = await start(
      const ListenerLimits(handshakeTimeout: Duration(milliseconds: 400)),
    );
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      h.server.port,
    );

    expect(await closesWithin(socket, const Duration(seconds: 5)), isTrue);
  });

  test('a connection without a certificate has a hard lifetime', () async {
    final h = await start(
      const ListenerLimits(noCertificateLifetime: Duration(seconds: 2)),
    );
    final secure = await tlsWithoutCertificate(h);
    final closed = closesWithin(secure, const Duration(seconds: 8));
    final watch = Stopwatch()..start();

    // HTTP/2 control traffic every 200 ms: the preface, SETTINGS frames and
    // a PING (the keepalive policy tolerates a few). None of it extends the
    // lifetime.
    secure.add(utf8.encode('PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n'));
    final settings = Uint8List.fromList([0, 0, 0, 4, 0, 0, 0, 0, 0]);
    final ping = Uint8List.fromList([
      0,
      0,
      8,
      6,
      0,
      0,
      0,
      0,
      0,
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
    ]);
    var sent = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      try {
        secure.add(sent++ == 5 ? ping : settings);
      } on Object {
        // Closed.
      }
    });

    expect(await closed, isTrue);
    timer.cancel();
    expect(watch.elapsed, greaterThan(const Duration(milliseconds: 1500)));
    expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
  });

  test('a paired device keeps its connection past that lifetime', () async {
    final h = await start(
      const ListenerLimits(noCertificateLifetime: Duration(milliseconds: 600)),
    );
    final device = await h.pair('desk-01');
    await device.system.getInfo(pb.GetInfoRequest());

    await Future<void>.delayed(const Duration(seconds: 2));

    expect((await device.system.getInfo(pb.GetInfoRequest())).devMode, isFalse);
  });

  test('addresses are counted per /64, IPv4-mapped ones as IPv4', () {
    expect(
      addressKey(InternetAddress('2001:db8:0:1::1')),
      addressKey(InternetAddress('2001:db8:0:1:ffff::9')),
    );
    expect(
      addressKey(InternetAddress('2001:db8:0:1::1')),
      isNot(addressKey(InternetAddress('2001:db8:0:2::1'))),
    );
    expect(
      addressKey(InternetAddress('::ffff:10.1.2.3')),
      addressKey(InternetAddress('10.1.2.3')),
    );
    expect(
      addressKey(InternetAddress('10.1.2.3')),
      isNot(addressKey(InternetAddress('10.1.2.4'))),
    );
  });
}
