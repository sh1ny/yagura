@Tags(['windows'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yagurad/src/admin/admin_client.dart';
import 'package:yagurad/src/admin/admin_server.dart';
import 'package:yagurad/src/admin/admin_wire.dart';
import 'package:yagurad/src/admin/named_pipe.dart';
import 'package:yagurad/src/errors.dart';

import '../support/admin_support.dart';

/// A server on a fresh test pipe whose handler echoes the command and keeps
/// every request it received.
class Echo {
  Echo._(this.name, this.server, this.requests);

  final String name;
  final AdminServer server;
  final List<AdminRequest> requests;

  static Future<Echo> start({
    int maxClients = maxAdminClients,
    Duration readTimeout = adminReadTimeout,
    Future<void> Function()? hold,
  }) async {
    final name = testPipeName();
    final requests = <AdminRequest>[];
    final server = AdminServer(
      NamedPipeListener(
        name: name,
        sddl: currentUserPipeSddl(),
        maxClients: maxClients,
      ),
      (request) async {
        requests.add(request);
        if (hold != null) await hold();
        return {'echo': request.command};
      },
      readTimeout: readTimeout,
    );
    await server.start();
    addTearDown(server.close);
    return Echo._(name, server, requests);
  }

  NamedPipeConnector connector({
    int maxMessageBytes = maxAdminMessage,
    Duration busyWait = const Duration(seconds: 5),
    void Function()? onBusy,
  }) => NamedPipeConnector(
    name: name,
    verifier: (_) => true,
    maxMessageBytes: maxMessageBytes,
    busyWait: busyWait,
    onBusy: onBusy,
  );

  AdminClient client({
    Duration readTimeout = adminReadTimeout,
    Duration busyWait = const Duration(seconds: 5),
    void Function()? onBusy,
  }) => AdminClient(
    connector(busyWait: busyWait, onBusy: onBusy),
    readTimeout: readTimeout,
  );
}

Future<void> expectReason(Future<Object?> call, String reason) => expectLater(
  call,
  throwsA(isA<YaguraException>().having((e) => e.reason, 'reason', reason)),
);

void main() {
  test('a_request_and_its_reply_cross_a_real_pipe', () async {
    final echo = await Echo.start();

    final result = await echo.client().call('status', {'verbose': true});

    expect(result, {'echo': 'status'});
    expect(echo.requests.single.args, {'verbose': true});
    expect(echo.server.serving, isTrue);
  });

  test('an_error_of_the_handler_reaches_the_client_with_its_reason', () async {
    final name = testPipeName();
    final server = AdminServer(
      NamedPipeListener(name: name, sddl: currentUserPipeSddl()),
      (request) async => throw YaguraException(
        'root_in_use',
        'in use by A',
        details: {'instance': 'A'},
      ),
    );
    await server.start();
    addTearDown(server.close);

    await expectLater(
      AdminClient(NamedPipeConnector(name: name, verifier: (_) => true))
          .call('roots.remove'),
      throwsA(
        isA<YaguraException>()
            .having((e) => e.reason, 'reason', 'root_in_use')
            .having((e) => e.message, 'message', 'in use by A')
            .having((e) => e.details, 'details', {'instance': 'A'}),
      ),
    );
  });

  test('a_second_server_on_the_name_is_a_squatter', () async {
    final first = await Echo.start();
    final second = NamedPipeListener(
      name: first.name,
      sddl: currentUserPipeSddl(),
    );

    await expectReason(second.open(), 'admin_channel_squatted');
    // The first server is untouched.
    expect(await first.client().call('status'), {'echo': 'status'});
  });

  test('closing_the_server_frees_the_name', () async {
    final first = await Echo.start();
    await first.server.close();
    expect(first.server.serving, isFalse);

    final again = NamedPipeListener(
      name: first.name,
      sddl: currentUserPipeSddl(),
    );
    await again.open();
    await again.close();
    await expectReason(first.client().call('status'), 'daemon_not_running');
  });

  test('a_message_over_64_kib_is_refused_before_it_is_read', () async {
    final echo = await Echo.start();
    // A client that does not enforce the bound itself.
    final connection = await echo.connector(maxMessageBytes: 1 << 20).connect();

    await connection.writeMessage(
      Uint8List.fromList(utf8.encode('x' * (maxAdminMessage + 1))),
    );
    final reply = decodeReply(
      await connection.readMessage(timeout: const Duration(seconds: 5)),
    );
    await connection.close();

    expect(reply.reason, 'message_too_large');
    expect(echo.requests, isEmpty);
  });

  test('a_message_just_under_64_kib_is_served', () async {
    final echo = await Echo.start();

    final reply = await echo.client().call('status', {
      'pad': 'x' * (maxAdminMessage - 200),
    });

    expect(reply, {'echo': 'status'});
  });

  test(
    'a_client_that_sends_nothing_is_dropped_after_the_read_timeout',
    () async {
      final echo = await Echo.start(
        readTimeout: const Duration(milliseconds: 300),
      );
      final connection = await echo.connector().connect();
      final watch = Stopwatch()..start();

      final reply = decodeReply(
        await connection.readMessage(timeout: const Duration(seconds: 5)),
      );
      await connection.close();

      expect(reply.reason, 'admin_request_timeout');
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
      expect(echo.requests, isEmpty);
      // The slot is free again.
      expect(await echo.client().call('status'), {'echo': 'status'});
    },
  );

  test('the_production_bounds_are_four_clients_and_a_five_second_read', () {
    expect(adminReadTimeout, const Duration(seconds: 5));
    expect(maxAdminClients, 4);
  });

  test('four_clients_are_served_at_once_and_the_fifth_waits', () async {
    final release = Completer<void>();
    final fourInside = Completer<void>();
    late final Echo echo;
    echo = await Echo.start(
      maxClients: 4,
      hold: () async {
        if (echo.requests.length == 4 && !fourInside.isCompleted) {
          fourInside.complete();
        }
        await release.future;
      },
    );
    // Nothing here depends on how long a step takes: the held clients wait
    // as long as it takes, and the test goes on when events say so.
    const forever = Duration(minutes: 5);

    // Four requests are inside the handler at the same time.
    final inFlight = [
      for (var i = 0; i < 4; i++)
        echo.client(readTimeout: forever, busyWait: forever).call('first-$i'),
    ];
    await fourInside.future;
    expect(echo.requests, hasLength(4));

    // The fifth finds every instance busy and keeps trying: it waits, it is
    // not refused. Three retries are seen, and still only four requests.
    final retried = Completer<void>();
    var retries = 0;
    var fifthDone = false;
    final fifth = echo
        .client(
          readTimeout: forever,
          busyWait: forever,
          onBusy: () {
            if (++retries == 3) retried.complete();
          },
        )
        .call('fifth')
        .whenComplete(() {
          fifthDone = true;
        });
    await retried.future;
    expect(fifthDone, isFalse);
    expect(echo.requests, hasLength(4));

    release.complete();
    expect(await Future.wait(inFlight), hasLength(4));
    expect(await fifth, {'echo': 'fifth'});
  });
}
