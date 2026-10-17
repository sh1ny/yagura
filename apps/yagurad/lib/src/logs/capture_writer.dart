import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'log_limits.dart';
import 'log_models.dart';

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
    this.encoding = LogEncoding.utf8,
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

  /// The encoding of the captured output: its line break is what a file may
  /// rotate after, and what ends a line that is being cut.
  final LogEncoding encoding;

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

  // Where the stream is in a line, kept across writes.
  var _lineLength = 0;
  var _dropping = false;

  /// Byte position within the encoding's code unit (always 0 for one-byte
  /// encodings), and whether the previous byte was the low byte of a line feed.
  var _phase = 0;
  var _lowLineFeed = false;

  late final Uint8List _lineBreak = Uint8List.fromList(
    encoding.unitBytes == 1 ? const [0x0A] : const [0x0A, 0x00],
  );

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
    _phase = size % encoding.unitBytes;
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
  /// line it is writing ends, never before, and a line break is the whole
  /// break of the [encoding] (`0A 00` for UTF-16LE), possibly split over two
  /// writes.
  ///
  /// A line is stored up to one unit more than the hub's line limit, which is
  /// enough for the hub to cut it and mark it `truncated`; the rest of it up
  /// to the next break is not stored, so output without a newline cannot grow
  /// a file past the bound.
  void write(List<int> bytes) {
    if (_closed) throw StateError('the capture writer is closed');
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final unit = encoding.unitBytes;
    final lineBytes = maxLineBytes + unit;
    var run = 0;
    for (var i = 0; i < data.length; i++) {
      final byte = data[i];
      final isLow = _phase == 0 && byte == 0x0A;
      final newline = unit == 1
          ? isLow
          : _lowLineFeed && _phase == 1 && byte == 0;
      _lowLineFeed = unit == 2 && isLow;
      _phase = (_phase + 1) % unit;
      if (_dropping) {
        run = i + 1;
        if (!newline) continue;
        _dropping = false;
        _lineLength = 0;
        _put(_lineBreak, 0, unit);
        if (_size >= fileBytes) _rotate();
        continue;
      }
      _lineLength++;
      if (newline) {
        _lineLength = 0;
        if (_size + (i + 1 - run) >= fileBytes) {
          _put(data, run, i + 1);
          _rotate();
          run = i + 1;
        }
      } else if (_lineLength > lineBytes) {
        _put(data, run, i);
        run = i + 1;
        _dropping = true;
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
