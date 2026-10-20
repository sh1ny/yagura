import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../files/files.dart';
import 'scrubber.dart';

/// Follows one of SteamCMD's log files while the run lives (design D15).
///
/// SteamCMD's stdout reaches the daemon only when the process exits, but it
/// writes `logs/console_log.txt` and `logs/connection_log.txt` as it goes. The
/// follower polls such a file and hands each new line to [onLine]:
///
///  - the file is opened without following links, through the installation's
///    [ConfinedFs], with full sharing, and closed again after each poll, so
///    SteamCMD can rotate or delete it;
///  - one poll reads at most [maxReadBytes];
///  - lines end at LF, a CR before it is dropped, and a line over
///    [maxLineBytes] keeps its first [maxLineBytes] bytes only;
///  - [stripTimestamp] removes the `[YYYY-MM-DD hh:mm:ss] ` prefix of
///    `console_log.txt`;
///  - a file that is smaller than the offset reached, or has another file id,
///    was rotated or truncated and is read again from its start;
///  - a file that is missing, or cannot be read, is "no signal yet", not an
///    error.
///
/// What the file held when [start] was called is skipped: [start] runs before
/// the process does. Every line goes through the [scrubber], then to
/// [onLine], and is dropped; the last [keptLines] are kept for a failure.
class SteamLogFollower {
  SteamLogFollower({
    required ConfinedFs fs,
    required this.path,
    required this.onLine,
    this.scrubber,
    this.stripTimestamp = false,
    this.pollInterval = const Duration(milliseconds: 250),
  }) : _fs = fs; // ignore: prefer_initializing_formals

  /// How much one poll reads.
  static const maxReadBytes = 64 * 1024;

  /// The longest line kept; the rest of a longer line is dropped.
  static const maxLineBytes = 4096;

  /// How many of the last lines are kept for [lastLines].
  static const keptLines = 5;

  final ConfinedFs _fs;

  /// The path below the fs root, for example `logs/console_log.txt`.
  final String path;
  final void Function(String line) onLine;
  final Scrubber? scrubber;
  final bool stripTimestamp;
  final Duration pollInterval;

  static final _timestamp = RegExp(
    r'^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] ',
  );

  Timer? _timer;
  var _started = false;
  var _offset = 0;
  var _fileId = '';
  final _line = <int>[];
  final _last = <String>[];

  /// How many lines were delivered so far.
  var lines = 0;

  /// The last [keptLines] lines delivered (scrubbed), oldest first.
  List<String> get lastLines => List.unmodifiable(_last);

  /// Notes where the file stands now and starts polling.
  void start() {
    if (_started) return;
    _started = true;
    try {
      final entry = _fs.stat(path);
      if (entry != null && !entry.isDirectory) {
        _offset = entry.size;
        _fileId = entry.fileId;
      }
    } on Object {
      // No signal yet: read from the start of whatever appears.
    }
    _timer = Timer.periodic(pollInterval, (_) => poll());
  }

  /// Reads what the file gained since the last poll.
  void poll() {
    final ConfinedEntry? entry;
    try {
      entry = _fs.stat(path);
    } on Object {
      return;
    }
    if (entry == null || entry.isDirectory || entry.isLink) return;
    if (entry.size < _offset ||
        (entry.fileId.isNotEmpty &&
            _fileId.isNotEmpty &&
            entry.fileId != _fileId)) {
      _offset = 0;
      _line.clear();
    }
    _fileId = entry.fileId;
    if (entry.size == _offset) return;
    Uint8List bytes;
    try {
      final reader = _fs.openRead(path);
      try {
        bytes = reader.readAt(_offset, maxReadBytes);
      } finally {
        reader.close();
      }
    } on Object {
      return;
    }
    _offset += bytes.length;
    for (final byte in bytes) {
      if (byte == 0x0a) {
        _endLine();
      } else if (_line.length < maxLineBytes) {
        // Past the limit the rest of the line is dropped.
        _line.add(byte);
      }
    }
  }

  void _endLine() {
    if (_line.isNotEmpty && _line.last == 0x0d) _line.removeLast();
    final bytes = List<int>.of(_line);
    _line.clear();
    var text = utf8.decode(bytes, allowMalformed: true);
    if (stripTimestamp) text = text.replaceFirst(_timestamp, '');
    if (scrubber != null) text = scrubber!.scrub(text);
    lines++;
    _last.add(text);
    if (_last.length > keptLines) _last.removeAt(0);
    onLine(text);
  }

  /// Polls once more, hands over a last line that has no end yet, and stops.
  void stop() {
    _timer?.cancel();
    _timer = null;
    if (!_started) return;
    poll();
    if (_line.isNotEmpty) _endLine();
    _started = false;
  }
}
