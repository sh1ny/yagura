import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'capture_writer.dart';
import 'line_assembler.dart';
import 'log_limits.dart';
import 'log_models.dart';

/// Where a tailer stopped: the file and the offset of the first byte it has
/// not turned into a line.
class LogPosition {
  const LogPosition(this.file, this.offset);
  final String file;
  final int offset;
}

typedef LineSink = void Function(
  String source,
  AssembledLine line, {
  required bool history,
});

/// Tails one log source by polling (design D6; `FileSystemEntity.watch` is
/// rejected because change notifications for appended data are unreliable on
/// some Windows volumes).
///
/// A poll resolves the source's file, follows rotation, detects truncation
/// and reads whatever was appended, one chunk at a time. Reading never takes
/// a lock the writer could notice: files are opened for reading only, which
/// the server can write through on both Windows and Linux.
class SourceTailer {
  SourceTailer({
    required this.spec,
    required this.sink,
    required this.onEvent,
    required this.clock,
    required this.waitingAfter,
    this.historyBytes = historyWindowBytes,
  }) : _assembler = LineAssembler(spec.encoding);

  final LogSourceSpec spec;
  final LineSink sink;
  final void Function(LogSourceEvent event) onEvent;
  final DateTime Function() clock;

  /// How long without a matching file before the source is `waiting`.
  final Duration waitingAfter;
  final int historyBytes;

  final LineAssembler _assembler;
  static const _chunkBytes = 256 * 1024;

  String? _current;
  var _offset = 0;
  var _known = <String>{};
  DateTime? _waitingSince;
  var _status = 'following';
  var _lastError = '';
  FixedFileMark? _mark;
  Future<void> _chain = Future<void>.value();

  // ---- state ---------------------------------------------------------------

  LogSourceStatus get status => LogSourceStatus(
    name: spec.name,
    kind: spec.kind,
    status: _status,
    currentFile: _current ?? '',
    encoding: spec.encoding,
    pattern: spec.pattern,
    lastError: _lastError,
  );

  /// What to save so a restart continues here; null before any file was seen.
  LogPosition? get position {
    final current = _current;
    if (current == null) return null;
    final held = _assembler.discarding ? 0 : _assembler.pendingBytes;
    return LogPosition(current, max(0, _offset - held));
  }

  // ---- start ---------------------------------------------------------------

  /// Resolves the file and refills the ring from its tail: up to the end of
  /// [saved] when the daemon was running before (the lines after it are read
  /// by the next poll and count as new), else up to the end of the file.
  Future<void> start(LogPosition? saved) async {
    try {
      final target = _target();
      var file = target;
      int? end;
      if (saved != null &&
          File(saved.file).existsSync() &&
          File(saved.file).lengthSync() >= saved.offset &&
          (spec.rotation == LogRotation.newest || saved.file == target)) {
        file = saved.file;
        end = saved.offset;
        if (spec.kind == LogSourceKind.file &&
            spec.rotation == LogRotation.newest &&
            target != null &&
            target != saved.file) {
          // A newer file appeared while the daemon was down: the next poll
          // drains the saved one and switches.
          _known.remove(target);
        }
      }
      if (file == null) {
        _waitingSince = clock();
        return;
      }
      _current = file;
      await _readHistory(file, end ?? File(file).lengthSync());
    } on FileSystemException catch (e) {
      _fail(e);
    }
  }

  Future<void> _readHistory(String path, int end) async {
    _offset = end;
    if (end == 0) return;
    final unit = spec.encoding.unitBytes;
    var from = end > historyBytes ? end - historyBytes : 0;
    from -= from % unit;
    final bytes = await _readRange(path, from, end - from);
    var start = 0;
    if (from > 0) {
      // Begin after the first line break: the window starts mid-line.
      start = bytes.length;
      for (var i = 0; i + unit <= bytes.length; i += unit) {
        if (bytes[i] == 0x0A && (unit == 1 || bytes[i + 1] == 0)) {
          start = i + unit;
          break;
        }
      }
    } else {
      start = _bomLength(bytes);
    }
    for (var at = start; at < bytes.length; at += _chunkBytes) {
      final stop = min(at + _chunkBytes, bytes.length);
      _feed(Uint8List.sublistView(bytes, at, stop), history: true);
    }
  }

  // ---- polling -------------------------------------------------------------

  /// Polls once. Calls are serialised: each one runs after the previous
  /// finished, so a caller that awaits it sees everything written before it.
  Future<void> poll() {
    final run = _chain.then((_) => _poll());
    _chain = run.catchError((Object _) {});
    return run;
  }

  Future<void> _poll() async {
    try {
      final current = _current;
      if (spec.kind == LogSourceKind.file &&
          current != null &&
          !File(current).existsSync()) {
        // Gone (or being recreated): a file that comes back is a new one.
        _current = null;
        _offset = 0;
        _assembler.reset();
      }
      if (_current == null) {
        final first = _target();
        if (first == null) {
          _noFile();
          return;
        }
        _found();
        _switchTo(first);
      } else {
        _found();
      }
      // Read the file to its end before moving on to the next one, so a
      // rotation never costs the last lines of the file it leaves.
      for (var hops = 0; hops < 10000; hops++) {
        await _readCurrent();
        final next = _target();
        if (next == null || next == _current) break;
        _switchTo(next);
      }
      _clearError();
    } on FileSystemException catch (e) {
      _fail(e);
    }
  }

  void _switchTo(String path) {
    final announce =
        spec.kind == LogSourceKind.file && spec.rotation == LogRotation.newest;
    _current = path;
    _offset = 0;
    _assembler.reset();
    if (announce) {
      onEvent(LogSourceEvent(spec.name, 'file_switched:${p.basename(path)}'));
    }
  }

  Future<void> _readCurrent() async {
    final path = _current!;
    final stat = File(path).statSync();
    if (stat.type == FileSystemEntityType.notFound) return;
    final size = stat.size;
    final mark = _mark;
    if (mark != null && await _rewritten(path, size, mark)) {
      _mark = null;
      _restart();
    } else if (size < _offset) {
      _restart();
    }
    if (size == _offset) return;
    final raf = await File(path).open();
    try {
      await raf.setPosition(_offset);
      var left = size - _offset;
      while (left > 0) {
        final chunk = await raf.read(min(left, _chunkBytes));
        if (chunk.isEmpty) break;
        left -= chunk.length;
        _consume(chunk);
      }
    } finally {
      await raf.close();
    }
  }

  void _restart() {
    _offset = 0;
    _assembler.reset();
  }

  void _consume(Uint8List chunk) {
    var data = chunk;
    if (_offset == 0) data = Uint8List.sublistView(chunk, _bomLength(chunk));
    _offset += chunk.length;
    _feed(data, history: false);
  }

  void _feed(Uint8List data, {required bool history}) {
    _assembler.add(data, (line) => sink(spec.name, line, history: history));
  }

  int _bomLength(Uint8List bytes) {
    final bom = spec.encoding.bom;
    if (bom.isEmpty || bytes.length < bom.length) return 0;
    for (var i = 0; i < bom.length; i++) {
      if (bytes[i] != bom[i]) return 0;
    }
    return bom.length;
  }

  Future<Uint8List> _readRange(String path, int from, int count) async {
    final raf = await File(path).open();
    try {
      await raf.setPosition(from);
      return await raf.read(count);
    } finally {
      await raf.close();
    }
  }

  // ---- which file ----------------------------------------------------------

  /// The file to read now, or null when none matches.
  String? _target() {
    switch (spec.kind) {
      case LogSourceKind.stdout:
        return _nextCapture();
      case LogSourceKind.file:
        if (spec.rotation == LogRotation.fixed) {
          return File(spec.pattern).existsSync() ? spec.pattern : null;
        }
        return _newest();
    }
  }

  /// Capture files are read in order, one after the other, so a rotation that
  /// happened while the daemon was down loses no line.
  String? _nextCapture() {
    final files = CaptureWriter.filesIn(spec.pattern);
    if (files.isEmpty) return null;
    final current = _current;
    if (current == null) return files.last;
    final at = CaptureWriter.sequenceOf(current)!;
    final next = files.where((f) => CaptureWriter.sequenceOf(f)! > at);
    if (next.isNotEmpty) return next.first;
    return files.contains(current) ? current : null;
  }

  /// The file a new `newest` source follows: the most recently created match.
  /// Later, only a file that was not there before can take over: Linux has no
  /// creation time to compare, and a file written to after a newer one
  /// appeared must not win.
  String? _newest() {
    final matches = _matches();
    if (matches.isEmpty) {
      _known = {};
      return null;
    }
    final previous = _known;
    _known = matches.toSet();
    final current = _current;
    if (current == null) return _mostRecent(matches);
    final appeared = [
      for (final m in matches)
        if (!previous.contains(m)) m,
    ];
    if (appeared.isNotEmpty) return _mostRecent(appeared);
    return matches.contains(current) ? current : _mostRecent(matches);
  }

  List<String> _matches() {
    final pattern = spec.pattern;
    final directory = p.dirname(pattern);
    final name = p.basename(pattern);
    if (!name.contains('*') && !name.contains('?')) {
      return File(pattern).existsSync() ? [pattern] : const [];
    }
    final dir = Directory(directory);
    if (!dir.existsSync()) return const [];
    final expression = RegExp(
      '^${name.splitMapJoin(RegExp(r'[*?]'), onMatch: (m) => m[0] == '*' ? '.*' : '.', onNonMatch: RegExp.escape)}\$',
      caseSensitive: !Platform.isWindows,
    );
    return [
      for (final entry in dir.listSync(followLinks: false))
        if (entry is File && expression.hasMatch(p.basename(entry.path)))
          entry.path,
    ];
  }

  String _mostRecent(List<String> files) {
    FileStat stat(String path) => File(path).statSync();
    var best = files.first;
    var bestStat = stat(best);
    for (final path in files.skip(1)) {
      final s = stat(path);
      final newer = switch (s.changed.compareTo(bestStat.changed)) {
        0 => switch (s.modified.compareTo(bestStat.modified)) {
          0 => path.compareTo(best) > 0,
          final byModified => byModified > 0,
        },
        final byCreated => byCreated > 0,
      };
      if (newer) {
        best = path;
        bestStat = s;
      }
    }
    return best;
  }

  // ---- status --------------------------------------------------------------

  void _noFile() {
    _waitingSince ??= clock();
    _clearError();
    if (_status != 'waiting' &&
        clock().difference(_waitingSince!) >= waitingAfter) {
      _status = 'waiting';
      onEvent(LogSourceEvent(spec.name, 'waiting'));
    }
  }

  void _found() {
    _waitingSince = null;
    if (_status == 'waiting') _status = 'following';
  }

  void _clearError() {
    if (_status == 'error') _status = 'following';
    _lastError = '';
  }

  void _fail(FileSystemException e) {
    final message = e.osError?.message.trim().isNotEmpty ?? false
        ? e.osError!.message.trim()
        : e.message;
    final changed = _lastError != message;
    _status = 'error';
    _lastError = message;
    if (changed) onEvent(LogSourceEvent(spec.name, 'error:$message'));
  }

  // ---- current-run mark ----------------------------------------------------

  /// Records the size and the SHA-256 of the first 4 KiB of a `fixed` file
  /// source (design D6); null for any other source. A later poll that finds a
  /// smaller size or a different hash reads the file from offset 0, so a
  /// rewrite that grows past the old size before the poll is still read.
  Future<FixedFileMark?> markRun() async {
    if (spec.kind != LogSourceKind.file || spec.rotation != LogRotation.fixed) {
      return null;
    }
    final mark = await _fingerprint(spec.pattern);
    _mark = mark;
    return mark;
  }

  Future<FixedFileMark> _fingerprint(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      return FixedFileMark(
        size: 0,
        hashedBytes: 0,
        sha256: sha256.convert(const []).toString(),
      );
    }
    final size = file.lengthSync();
    final head = await _readRange(path, 0, min(size, markHashBytes));
    return FixedFileMark(
      size: size,
      hashedBytes: head.length,
      sha256: sha256.convert(head).toString(),
    );
  }

  Future<bool> _rewritten(String path, int size, FixedFileMark mark) async {
    if (size < mark.size) return true;
    if (mark.hashedBytes == 0) return false;
    final head = await _readRange(path, 0, mark.hashedBytes);
    return head.length < mark.hashedBytes ||
        sha256.convert(head).toString() != mark.sha256;
  }
}
