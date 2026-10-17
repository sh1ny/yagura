import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import 'process_support.dart';

/// Names a Valheim dedicated server install the `valheim` test copies into
/// the instance instead of downloading ~2.1 GB with SteamCMD.
const valheimServerEnvironment = 'YAGURA_VALHEIM_SERVER';

/// A real `yagurad run --dev` process on a private data directory, driven
/// over gRPC with the generated client. Everything it started (the daemon,
/// the relays and the servers recorded in `relay.json`) is ended by [close].
class DaemonProcess {
  DaemonProcess._(this.process, this.port, this.dataDirectory, this._output);

  final Process process;
  final int port;
  final String dataDirectory;
  final StringBuffer _output;
  late final ClientChannel channel = ClientChannel(
    '127.0.0.1',
    port: port,
    options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
  );

  late final instances = pb.InstancesClient(channel);
  late final operations = pb.OperationsClient(channel);

  /// What the daemon wrote to stdout and stderr so far.
  String get output => _output.toString();

  /// Starts [yagurad] (`run --dev`) on [dataDirectory] and waits until it
  /// listens.
  static Future<DaemonProcess> start(
    String yagurad,
    String dataDirectory,
  ) async {
    final port = await _freePort();
    final output = StringBuffer();
    final process = await Process.start(yagurad, [
      'run',
      '--dev',
      '--data-dir',
      dataDirectory,
      '--bind',
      '127.0.0.1:$port',
    ]);
    final listening = Completer<void>();
    process.stdout.transform(utf8.decoder).listen((text) {
      output.write(text);
      if (text.contains('listening on') && !listening.isCompleted) {
        listening.complete();
      }
    });
    process.stderr.transform(utf8.decoder).listen(output.write);
    unawaited(
      process.exitCode.then((code) {
        if (!listening.isCompleted) {
          listening.completeError(
            StateError('yagurad exited with $code:\n$output'),
          );
        }
      }),
    );
    final daemon = DaemonProcess._(process, port, dataDirectory, output);
    try {
      await listening.future.timeout(const Duration(seconds: 30));
    } on Object {
      await daemon.close();
      rethrow;
    }
    return daemon;
  }

  /// Polls [started] until it ends; fails the test when it does not succeed.
  Future<pb.Operation> succeeded(
    pb.Operation started, {
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var op = started;
    while (true) {
      switch (op.status) {
        case pb.OperationStatus.OPERATION_STATUS_SUCCEEDED:
          return op;
        case pb.OperationStatus.OPERATION_STATUS_FAILED ||
            pb.OperationStatus.OPERATION_STATUS_CANCELLED ||
            pb.OperationStatus.OPERATION_STATUS_INTERRUPTED:
          fail(
            'operation ${op.id} ended ${op.status.name}: ${op.resultReason} '
            '${op.resultMessage}\n--- daemon output ---\n$output',
          );
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

  /// Every server and relay PID recorded under the data directory.
  Set<int> recordedPids() {
    final pids = <int>{};
    final root = Directory(dataDirectory);
    if (!root.existsSync()) return pids;
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || p.basename(entity.path) != 'relay.json') continue;
      try {
        final json = jsonDecode(entity.readAsStringSync()) as Map;
        for (final key in ['relay_pid', 'server_pid']) {
          if (json[key] case final int pid) pids.add(pid);
        }
      } on Object {
        // A half-written file names nobody.
      }
    }
    return pids;
  }

  /// Ends the daemon, then every recorded relay and server still alive.
  Future<void> close() async {
    await channel.terminate();
    process.kill();
    await process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    final pids = {...recordedPids(), process.pid};
    for (final pid in pids) {
      if (processAlive(pid)) Process.killPid(pid);
    }
    for (var i = 0; i < 100 && pids.any(processAlive); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// Copies the directory tree [from] to [to].
void copyDirectory(String from, String to) {
  Directory(to).createSync(recursive: true);
  for (final entity in Directory(
    from,
  ).listSync(recursive: true, followLinks: false)) {
    final target = p.join(to, p.relative(entity.path, from: from));
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      Directory(p.dirname(target)).createSync(recursive: true);
      entity.copySync(target);
    }
  }
}

/// Deletes [directory], retrying while a just-ended process still holds
/// files in it.
Future<void> deleteDirectory(Directory directory) async {
  for (var i = 0; i < 30; i++) {
    if (!directory.existsSync()) return;
    try {
      directory.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
}
