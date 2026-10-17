/// Held-line bookkeeping for the log view (desktop-client, "Logs and console
/// views").
library;

import 'dart:collection';

sealed class LogItem {
  const LogItem();
}

final class LogLineItem extends LogItem {
  const LogLineItem({
    required this.source,
    required this.text,
    required this.sequence,
  });

  final String source;
  final String text;
  final int sequence;
}

/// Inline notice for lines that were skipped.
final class DroppedNotice extends LogItem {
  const DroppedNotice(this.count);

  final int count;
}

/// Maximum new lines a paused view holds.
const int kMaxHeldLines = 10000;

/// Lines (and notices) shown by a log view. While paused, new items are held;
/// beyond [maxHeld] lines the oldest held ones are dropped and counted.
class LogBuffer {
  LogBuffer({this.maxHeld = kMaxHeldLines, this.maxLoaded = 50000});

  final int maxHeld;

  /// Loaded items kept for the view; older ones fall off the front.
  final int maxLoaded;

  final List<LogItem> _items = [];
  final Queue<LogItem> _held = Queue();
  bool _paused = false;
  int _heldLines = 0;
  int _heldDropped = 0;

  List<LogItem> get items => _items;
  bool get paused => _paused;

  /// Lines held back while paused.
  int get heldLines => _heldLines;

  /// Lines dropped from the held ones so far in this pause.
  int get heldDropped => _heldDropped;

  void add(LogItem item) {
    if (!_paused) {
      _append(item);
      return;
    }
    _held.addLast(item);
    if (item is LogLineItem) _heldLines++;
    while (_heldLines > maxHeld) {
      switch (_held.removeFirst()) {
        case LogLineItem():
          _heldLines--;
          _heldDropped++;
        case DroppedNotice(:final count):
          _heldDropped += count;
      }
    }
  }

  void pause() => _paused = true;

  /// Shows what was held: a notice for dropped lines, then the rest in order.
  void resume() {
    if (!_paused) return;
    _paused = false;
    if (_heldDropped > 0) _append(DroppedNotice(_heldDropped));
    _held.forEach(_append);
    _held.clear();
    _heldLines = 0;
    _heldDropped = 0;
  }

  void _append(LogItem item) {
    _items.add(item);
    // Trim in chunks so a busy log does not shift the list on every line.
    if (_items.length > maxLoaded + 1000) {
      _items.removeRange(0, _items.length - maxLoaded);
    }
  }
}
