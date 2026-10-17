import 'dart:convert';
import 'dart:typed_data';

/// Encodings a log source can declare (`log-streaming` spec).
enum LogEncoding {
  utf8('utf-8'),
  utf16le('utf-16le'),
  latin1('latin-1');

  const LogEncoding(this.wireName);

  final String wireName;

  /// The spec's names: `utf-8`, `utf-16le`, `latin-1`.
  static LogEncoding? parse(String name) => switch (name.toLowerCase()) {
    'utf-8' => utf8,
    'utf-16le' => utf16le,
    'latin-1' => latin1,
    _ => null,
  };

  /// Bytes per code unit; line breaks are found on this grid.
  int get unitBytes => this == utf16le ? 2 : 1;

  /// Decodes [bytes], replacing what cannot be decoded with U+FFFD.
  String decode(List<int> bytes) {
    switch (this) {
      case utf8:
        return const Utf8Decoder(allowMalformed: true).convert(bytes);
      case latin1:
        return const Latin1Decoder(allowInvalid: true).convert(bytes);
      case utf16le:
        final units = Uint16List(bytes.length ~/ 2);
        for (var i = 0; i < units.length; i++) {
          units[i] = bytes[2 * i] | (bytes[2 * i + 1] << 8);
        }
        final out = StringBuffer();
        for (var i = 0; i < units.length; i++) {
          final unit = units[i];
          if (unit >= 0xD800 && unit <= 0xDBFF) {
            if (i + 1 < units.length &&
                units[i + 1] >= 0xDC00 &&
                units[i + 1] <= 0xDFFF) {
              out.writeCharCode(unit);
              out.writeCharCode(units[++i]);
            } else {
              out.write('�');
            }
          } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
            out.write('�');
          } else {
            out.writeCharCode(unit);
          }
        }
        // A trailing odd byte is half a code unit.
        if (bytes.length.isOdd) out.write('�');
        return out.toString();
    }
  }

  /// The byte-order mark this encoding may start a file with.
  List<int> get bom => switch (this) {
    utf8 => const [0xEF, 0xBB, 0xBF],
    utf16le => const [0xFF, 0xFE],
    latin1 => const [],
  };
}

enum LogSourceKind {
  stdout,
  file;

  String get wireName => name;
}

/// `newest` picks the most recently created matching file; `fixed` follows
/// one path across truncation.
enum LogRotation { newest, fixed }

/// A log source of an instance, with its pattern already rendered to an
/// absolute path.
class LogSourceSpec {
  const LogSourceSpec({
    required this.name,
    required this.kind,
    required this.encoding,
    this.pattern = '',
    this.rotation = LogRotation.fixed,
  });

  /// The `stdout` capture of an instance, in the capture [directory].
  const LogSourceSpec.stdout({
    required this.name,
    required this.encoding,
    required String directory,
  }) : kind = LogSourceKind.stdout,
       pattern = directory,
       rotation = LogRotation.newest;

  final String name;
  final LogSourceKind kind;

  /// Absolute path or glob (wildcards in the file name only) of a file
  /// source; the capture directory for `stdout`.
  final String pattern;
  final LogEncoding encoding;
  final LogRotation rotation;

  @override
  bool operator ==(Object other) =>
      other is LogSourceSpec &&
      other.name == name &&
      other.kind == kind &&
      other.pattern == pattern &&
      other.encoding == encoding &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(name, kind, pattern, encoding, rotation);

  @override
  String toString() => 'LogSourceSpec($name ${kind.name} $pattern)';
}

/// One decoded line (`LogEntry` of `logs.proto`).
class LogEntry {
  const LogEntry({
    required this.source,
    required this.sequence,
    required this.receivedAt,
    required this.text,
    required this.sizeBytes,
    this.truncated = false,
  });

  final String source;

  /// Increases by one per line of an instance, across its sources.
  final int sequence;
  final DateTime receivedAt;

  /// Decoded text without the line break.
  final String text;

  /// The line's size on disk, which the memory bounds count.
  final int sizeBytes;

  /// The line was longer than 64 KiB and was cut; the rest was discarded.
  final bool truncated;

  @override
  String toString() => 'LogEntry($source #$sequence $text)';
}

/// What a `Follow` stream delivers (`LogBatch` of `logs.proto`): lines, or a
/// [sourceEvent] of [source], with the lines [dropped] before it.
class LogBatch {
  const LogBatch({
    this.entries = const [],
    this.dropped = 0,
    this.source = '',
    this.sourceEvent = '',
  });

  final List<LogEntry> entries;

  /// Lines skipped before this batch because the subscriber lagged.
  final int dropped;

  /// The source a [sourceEvent] is about.
  final String source;

  /// `file_switched:<name>`, `waiting` or `error:<message>`; empty for lines.
  final String sourceEvent;

  @override
  String toString() =>
      'LogBatch(${entries.length} lines, dropped $dropped, $sourceEvent)';
}

/// The answer to a backlog request.
class LogBacklog {
  const LogBacklog(this.entries, {required this.truncated});

  /// Oldest first.
  final List<LogEntry> entries;

  /// The request asked for more than the 5,000-line cap.
  final bool truncated;
}

/// A source's state (`LogSource` of `logs.proto`).
class LogSourceStatus {
  const LogSourceStatus({
    required this.name,
    required this.kind,
    required this.status,
    required this.currentFile,
    required this.encoding,
    required this.pattern,
    required this.lastError,
  });

  final String name;
  final LogSourceKind kind;

  /// `following`, `waiting` or `error`.
  final String status;
  final String currentFile;
  final LogEncoding encoding;

  /// The pattern a `waiting` source looks for.
  final String pattern;
  final String lastError;
}

/// A source event with the source it belongs to.
class LogSourceEvent {
  const LogSourceEvent(this.source, this.event);
  final String source;
  final String event;
}

/// The current-run mark of one `fixed` file source (design D6): size and
/// SHA-256 of the first bytes of its file, taken before a Start.
class FixedFileMark {
  const FixedFileMark({
    required this.size,
    required this.hashedBytes,
    required this.sha256,
  });

  final int size;

  /// How many head bytes [sha256] covers: at most 4 KiB, less for a smaller
  /// file.
  final int hashedBytes;
  final String sha256;
}

/// The current-run mark of an instance: lines of its sources with a larger
/// sequence than [sequence] were read after it.
class LogRunMark {
  const LogRunMark({required this.sequence, required this.fixedFiles});

  final int sequence;
  final Map<String, FixedFileMark> fixedFiles;
}

/// How much a source's ring buffer holds.
class LogBufferStats {
  const LogBufferStats({required this.lines, required this.bytes});
  final int lines;
  final int bytes;
}
