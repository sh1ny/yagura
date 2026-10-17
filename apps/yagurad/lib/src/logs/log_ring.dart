import 'dart:collection';

import 'log_limits.dart';
import 'log_models.dart';

/// The last lines of one source: at most [maxLines] lines and [maxBytes]
/// bytes, the oldest evicted first.
class LogRing {
  LogRing({this.maxLines = ringMaxLines, this.maxBytes = ringMaxBytes});

  final int maxLines;
  final int maxBytes;
  final _entries = Queue<LogEntry>();
  var _bytes = 0;

  int get length => _entries.length;
  int get bytes => _bytes;

  Iterable<LogEntry> get entries => _entries;

  void add(LogEntry entry) {
    _entries.addLast(entry);
    _bytes += entry.sizeBytes;
    while (_entries.length > maxLines || _bytes > maxBytes) {
      _bytes -= _entries.removeFirst().sizeBytes;
    }
  }

  /// The newest [count] lines, oldest first.
  List<LogEntry> last(int count) {
    final skip = _entries.length > count ? _entries.length - count : 0;
    return _entries.skip(skip).toList();
  }
}
