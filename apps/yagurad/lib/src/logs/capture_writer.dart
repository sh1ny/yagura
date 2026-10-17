import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'log_limits.dart';

/// Writes the stdout capture of one instance: numbered files that rotate at
/// [fileBytes] and only at line boundaries, so no line is split across two
/// files, keeping the newest [fileCount].
///
/// The relay (task 5.2) owns the server's stdout and stderr pipes and calls
/// this, so the capture keeps growing while the daemon is down. The log hub
/// reads the files back (`LogSourceSpec.stdout`).
///
/// Location: `<instance directory>/.yagura/logs/`, see [directoryFor]. The
/// capture belongs to the instance, not to a run: the 10 MiB x 5 files bound is
/// per instance (`openspec/architecture.md`, Resource Bounds), so it does not
/// move into a run directory (`.yagura/run/<run-id>/`, which holds the
/// `relay.json` and `exit.json` of one run). Files are numbered and never
/// renamed, so a reader holding one open is not disturbed on either OS.
class CaptureWriter {
  CaptureWriter.open(
    this.directory, {
    this.fileBytes = captureFileBytes,
    this.fileCount = captureFileCount,
  }) {
    Directory(directory).createSync(recursive: true);
    _resume();
  }

  static const _prefix = 'capture-';
  static const _suffix = '.log';

  final String directory;

  /// A file rotates once it holds at least this many bytes and a line ends.
  final int fileBytes;

  /// How many files are kept, the newest.
  final int fileCount;

  /// The capture directory of an instance.
  static String directoryFor(String instanceDirectory) =>
      p.join(instanceDirectory, '.yagura', 'logs');

  /// The sequence number in a capture file name, or null for another file.
  static int? sequenceOf(String path) {
    final name = p.basename(path);
    if (!name.startsWith(_prefix) || !name.endsWith(_suffix)) return null;
    return int.tryParse(
      name.substring(_prefix.length, name.length - _suffix.length),
    );
  }

  /// The capture files in [directory], oldest first.
  static List<String> filesIn(String directory) {
    final dir = Directory(directory);
    if (!dir.existsSync()) return const [];
    final files = <(int, String)>[];
    try {
      for (final entry in dir.listSync(followLinks: false)) {
        if (entry is! File) continue;
        if (sequenceOf(entry.path) case final sequence?) {
          files.add((sequence, entry.path));
        }
      }
    } on FileSystemException {
      return const [];
    }
    files.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, path) in files) path];
  }

  static String _name(int sequence) =>
      '$_prefix${sequence.toString().padLeft(6, '0')}$_suffix';

  RandomAccessFile? _file;
  var _sequence = 0;
  var _size = 0;
  var _closed = false;

  /// Continues the newest file when it still has room (after a restart of the
  /// writer), else the next write starts a new one.
  void _resume() {
    final files = filesIn(directory);
    if (files.isEmpty) return;
    final last = files.last;
    _sequence = sequenceOf(last)!;
    final size = File(last).lengthSync();
    if (size >= fileBytes) return;
    _file = File(last).openSync(mode: FileMode.append);
    _size = size;
  }

  void _open() {
    _sequence++;
    final path = p.join(directory, _name(_sequence));
    _file = File(path).openSync(mode: FileMode.append);
    _size = 0;
    final files = filesIn(directory);
    final surplus = files.length - fileCount;
    for (final old in surplus > 0 ? files.take(surplus) : const <String>[]) {
      try {
        File(old).deleteSync();
      } on FileSystemException {
        // A reader may still hold it; the next rotation tries again.
      }
    }
  }

  void _put(Uint8List bytes, int start, int end) {
    if (end <= start) return;
    final file =
        _file ??
        (() {
          _open();
          return _file!;
        })();
    file
      ..writeFromSync(bytes, start, end)
      ..flushSync();
    _size += end - start;
  }

  void _rotate() {
    _file?.closeSync();
    _file = null;
  }

  /// Appends [bytes]. A file that has reached [fileBytes] rotates when the
  /// line it is writing ends, never before.
  void write(List<int> bytes) {
    if (_closed) throw StateError('the capture writer is closed');
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    var run = 0;
    for (var i = 0; i < data.length; i++) {
      if (data[i] != 0x0A) continue;
      final end = i + 1;
      if (_size + (end - run) >= fileBytes) {
        _put(data, run, end);
        _rotate();
        run = end;
      }
    }
    _put(data, run, data.length);
  }

  void close() {
    _closed = true;
    _file?.closeSync();
    _file = null;
  }
}
