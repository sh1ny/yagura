import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yagura_proto/yagura_proto.dart';

import '../connection.dart';
import '../log_buffer.dart';
import '../providers.dart';

/// State of one instance's log view: backlog, live follow, pause and search.
class LogViewController extends ChangeNotifier {
  LogViewController({required this.connection, required this.instanceId});

  final DaemonConnection connection;
  final String instanceId;

  final LogBuffer _buffer = LogBuffer();
  final List<LogBatch> _liveBeforeBacklog = [];
  StreamSubscription<LogBatch>? _backlogSub;
  StreamSubscription<LogBatch>? _followSub;
  bool _backlogDone = false;

  /// Highest sequence the backlog delivered; sequences grow across an
  /// instance's sources, so live lines at or below it are already shown.
  int _backlogLast = 0;
  bool _disposed = false;
  String _search = '';

  /// A failure the view shows instead of more lines; null when all is well.
  String? error;

  /// Loaded items, filtered by [search]. Notices stay in the list.
  List<LogItem> get items {
    final query = _search.toLowerCase();
    if (query.isEmpty) return _buffer.items;
    return [
      for (final item in _buffer.items)
        if (item is! LogLineItem || item.text.toLowerCase().contains(query))
          item,
    ];
  }

  bool get paused => _buffer.paused;

  /// New lines counted but not yet shown while paused.
  int get heldLines => _buffer.heldLines;

  String get search => _search;

  set search(String value) {
    _search = value;
    notifyListeners();
  }

  /// Loads the backlog and follows live lines. Live batches that arrive before
  /// the backlog is complete wait for it, so lines stay in order.
  void start() {
    _followSub = connection
        .followLogs(instanceId)
        .listen(_onLive, onError: _onError);
    _backlogSub = connection
        .backlog(instanceId)
        .listen(
          (batch) {
            for (final entry in batch.entries) {
              final sequence = entry.sequence.toInt();
              if (sequence > _backlogLast) _backlogLast = sequence;
            }
            _ingest(batch);
          },
          onError: _onError,
          onDone: () {
            _backlogDone = true;
            for (final batch in _liveBeforeBacklog) {
              // The daemon also delivers lines that arrived between the two
              // requests to the follower.
              _ingest(
                LogBatch(
                  dropped: batch.dropped,
                  entries: [
                    for (final e in batch.entries)
                      if (e.sequence.toInt() > _backlogLast) e,
                  ],
                ),
              );
            }
            _liveBeforeBacklog.clear();
          },
        );
  }

  void _onLive(LogBatch batch) {
    if (_backlogDone) {
      _ingest(batch);
    } else {
      _liveBeforeBacklog.add(batch);
    }
  }

  void _onError(Object e, StackTrace _) {
    error = e.toString();
    if (!_disposed) notifyListeners();
  }

  void _ingest(LogBatch batch) {
    if (batch.dropped > 0) {
      _buffer.add(DroppedNotice(batch.dropped.toInt()));
    }
    for (final entry in batch.entries) {
      _buffer.add(
        LogLineItem(
          source: entry.source,
          text: entry.text,
          sequence: entry.sequence.toInt(),
        ),
      );
    }
    if (!_disposed) notifyListeners();
  }

  void pause() {
    _buffer.pause();
    notifyListeners();
  }

  /// Shows the held lines; returns how many held lines had been dropped.
  int resume() {
    final dropped = _buffer.heldDropped;
    _buffer.resume();
    notifyListeners();
    return dropped;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_backlogSub?.cancel());
    unawaited(_followSub?.cancel());
    super.dispose();
  }
}

class LogView extends ConsumerStatefulWidget {
  const LogView({
    super.key,
    required this.daemonId,
    required this.instanceId,
    this.controller,
  });

  final String daemonId;
  final String instanceId;

  /// Supplied by tests; the view owns (and disposes) its own otherwise.
  final LogViewController? controller;

  @override
  ConsumerState<LogView> createState() => _LogViewState();
}

class _LogViewState extends ConsumerState<LogView> {
  static const _lineHeight = 20.0;

  late final LogViewController _controller;
  late final bool _owned;
  final _scroll = ScrollController();

  /// Whether new lines keep the view at the bottom.
  bool _stick = true;

  @override
  void initState() {
    super.initState();
    _owned = widget.controller == null;
    _controller =
        widget.controller ??
        LogViewController(
          connection: ref.read(daemonConnectionProvider(widget.daemonId)),
          instanceId: widget.instanceId,
        );
    if (_owned) _controller.start();
    _controller.addListener(_followBottom);
    _scroll.addListener(() {
      final position = _scroll.position;
      _stick = position.pixels >= position.maxScrollExtent - _lineHeight;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_followBottom);
    if (_owned) _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _followBottom() {
    if (!_stick || _controller.paused) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients && _stick && !_controller.paused) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _togglePause() {
    if (_controller.paused) {
      final dropped = _controller.resume();
      // Stay at the notice when lines were dropped, so it is seen.
      if (dropped > 0) _stick = false;
      _followBottom();
    } else {
      _controller.pause();
    }
  }

  void _jumpToLatest() {
    _stick = true;
    _followBottom();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final items = _controller.items;
        final scheme = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('log:search'),
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search loaded lines',
                      ),
                      onChanged: (v) => _controller.search = v,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('log:pause'),
                    tooltip: _controller.paused ? 'Resume' : 'Pause',
                    icon: Icon(
                      _controller.paused ? Icons.play_arrow : Icons.pause,
                    ),
                    onPressed: _togglePause,
                  ),
                  IconButton(
                    key: const ValueKey('log:latest'),
                    tooltip: 'Jump to latest',
                    icon: const Icon(Icons.vertical_align_bottom),
                    onPressed: _jumpToLatest,
                  ),
                ],
              ),
            ),
            if (_controller.paused)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('Paused: ${_controller.heldLines} new lines'),
              ),
            if (_controller.error case final error?)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(error, style: TextStyle(color: scheme.error)),
              ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                itemExtent: _lineHeight,
                itemCount: items.length,
                itemBuilder: (context, index) => switch (items[index]) {
                  LogLineItem(:final text) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  DroppedNotice(:final count) => Container(
                    color: scheme.tertiaryContainer,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$count lines skipped',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
