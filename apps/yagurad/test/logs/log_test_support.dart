import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/files/files.dart';
import 'package:yagurad/src/logs/logs.dart';

/// The instance id the hub-level tests use.
const rigInstance = 'inst';

/// A log hub over a temporary directory, without a daemon. By default it
/// polls only when a test calls `pollNow`.
class LogRig {
  LogRig({
    DateTime Function()? clock,
    LogHubOptions options = const LogHubOptions.manual(),
  }) : dir = Directory.systemTemp.createTempSync('yagurad_logs_') {
    hub = LogHub(clock: clock, options: options);
    addTearDown(() async {
      await hub.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
  }

  final Directory dir;
  late final LogHub hub;

  String path(String name) => p.join(dir.path, name);

  /// Creates or replaces a file.
  void write(String name, List<int> bytes) {
    final file = File(path(name));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
  }

  /// Appends to a file, creating it.
  void append(String name, List<int> bytes) {
    final file = File(path(name));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes, mode: FileMode.append);
  }

  /// Appends text lines (each followed by `\n`).
  void appendLines(String name, Iterable<String> lines) =>
      append(name, utf8.encode('${lines.join('\n')}\n'));

  /// A `fixed` UTF-8 file source at [name] in the temporary directory.
  LogSourceSpec fileSource(
    String source,
    String name, {
    LogEncoding encoding = LogEncoding.utf8,
    LogRotation rotation = LogRotation.fixed,
  }) => LogSourceSpec(
    name: source,
    kind: LogSourceKind.file,
    pattern: path(name),
    encoding: encoding,
    rotation: rotation,
  );

  Future<void> attach(List<LogSourceSpec> sources) =>
      hub.attach(rigInstance, sources, fs: InstanceFs(dir.path));

  Future<void> poll() => hub.pollNow(rigInstance);
}

/// Collects what a `Follow` stream delivers.
class Collector {
  Collector(Stream<LogBatch> stream) {
    subscription = stream.listen(batches.add);
    addTearDown(subscription.cancel);
  }

  final batches = <LogBatch>[];
  late final StreamSubscription<LogBatch> subscription;

  List<LogEntry> get entries => [for (final b in batches) ...b.entries];
  List<String> get texts => [for (final e in entries) e.text];
  List<String> get events => [
    for (final b in batches)
      if (b.sourceEvent.isNotEmpty) b.sourceEvent,
  ];
  int get dropped => batches.fold(0, (sum, b) => sum + b.dropped);

  /// Lets queued stream events reach the listener.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));
}

/// `line 0001`, `line 0002`...
List<String> numberedLines(int count, {int from = 1}) => [
  for (var i = from; i < from + count; i++)
    'line ${i.toString().padLeft(5, '0')}',
];
