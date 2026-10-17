import 'dart:typed_data';

import 'log_limits.dart';
import 'log_models.dart';

/// A line cut out of a byte stream, not yet decoded.
class AssembledLine {
  const AssembledLine(this.bytes, {this.truncated = false});

  /// The line without its break (and without a `\r` before it).
  final Uint8List bytes;

  /// The line was longer than the limit and was cut there.
  final bool truncated;
}

/// Splits a byte stream into lines on the encoding's own line break (`0A 00`
/// for UTF-16LE). A line longer than [maxBytes] is cut there and delivered
/// with `truncated`; the rest of it, up to the next break, is discarded. Memory
/// stays within [maxBytes] however much arrives without a newline.
class LineAssembler {
  LineAssembler(this.encoding, {this.maxBytes = maxLineBytes});

  final LogEncoding encoding;
  final int maxBytes;

  final _line = BytesBuilder();
  int? _half;
  var _discarding = false;

  /// Bytes of an unfinished line held back.
  int get pendingBytes => _line.length + (_half == null ? 0 : 1);

  /// The rest of a cut line is being thrown away.
  bool get discarding => _discarding;

  void reset() {
    _line.clear();
    _half = null;
    _discarding = false;
  }

  /// Feeds [chunk]; calls [onLine] for every line it completes.
  void add(Uint8List chunk, void Function(AssembledLine line) onLine) {
    if (encoding.unitBytes == 1) {
      _addBytes(chunk, onLine);
    } else {
      _addUnits(chunk, onLine);
    }
  }

  void _addBytes(Uint8List chunk, void Function(AssembledLine) onLine) {
    var at = 0;
    while (at < chunk.length) {
      final newline = chunk.indexOf(0x0A, at);
      final end = newline < 0 ? chunk.length : newline;
      if (!_discarding && end > at) {
        final room = maxBytes - _line.length;
        if (end - at <= room) {
          _line.add(Uint8List.sublistView(chunk, at, end));
        } else {
          _line.add(Uint8List.sublistView(chunk, at, at + room));
          _cut(onLine);
        }
      }
      if (newline < 0) return;
      _finish(onLine);
      at = newline + 1;
    }
  }

  void _addUnits(Uint8List chunk, void Function(AssembledLine) onLine) {
    for (final byte in chunk) {
      final low = _half;
      if (low == null) {
        _half = byte;
        continue;
      }
      _half = null;
      if (low == 0x0A && byte == 0) {
        _finish(onLine);
      } else if (!_discarding) {
        if (_line.length + 2 > maxBytes) {
          _cut(onLine);
        } else {
          _line
            ..addByte(low)
            ..addByte(byte);
        }
      }
    }
  }

  void _cut(void Function(AssembledLine) onLine) {
    _discarding = true;
    onLine(AssembledLine(_line.takeBytes(), truncated: true));
  }

  void _finish(void Function(AssembledLine) onLine) {
    if (_discarding) {
      _discarding = false;
      return;
    }
    final bytes = _line.takeBytes();
    onLine(AssembledLine(_withoutCarriageReturn(bytes)));
  }

  Uint8List _withoutCarriageReturn(Uint8List bytes) {
    if (encoding.unitBytes == 1) {
      if (bytes.isNotEmpty && bytes.last == 0x0D) {
        return Uint8List.sublistView(bytes, 0, bytes.length - 1);
      }
    } else if (bytes.length >= 2 &&
        bytes[bytes.length - 2] == 0x0D &&
        bytes.last == 0) {
      return Uint8List.sublistView(bytes, 0, bytes.length - 2);
    }
    return bytes;
  }
}
