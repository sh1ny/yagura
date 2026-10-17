import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../host/daemon.dart';
import '../logs/log_models.dart';
import 'convert.dart';
import 'pressure.dart';
import 'service_support.dart';

/// A backlog message holds at most this many lines or bytes of text, so one
/// message stays far below the 16 MiB response limit and no line is split.
const backlogPageLines = 1000;
const backlogPageBytes = 1024 * 1024;

/// The `Logs` service.
class LogsApi extends pb.LogsServiceBase with GuardedService {
  LogsApi(this.daemon, this.logSink);

  final Daemon daemon;

  @override
  final LogSink logSink;

  @override
  Future<pb.ListSourcesResponse> listSources(
    ServiceCall call,
    pb.ListSourcesRequest request,
  ) async {
    _requireInstance(request.instanceId);
    return pb.ListSourcesResponse(
      sources: [
        for (final s in daemon.logs.sources(request.instanceId))
          logSourceToPb(s),
      ],
    );
  }

  /// Up to 5,000 lines, oldest first, paged across messages.
  @override
  Stream<pb.LogBatch> backlog(
    ServiceCall call,
    pb.BacklogRequest request,
  ) async* {
    _requireInstance(request.instanceId);
    final backlog = daemon.logs.backlog(
      request.instanceId,
      sources: request.sources.toSet(),
      lines: request.lines,
    );
    var page = <pb.LogEntry>[];
    var bytes = 0;
    var first = true;
    pb.LogBatch flush() {
      final batch = pb.LogBatch(
        entries: page,
        truncated: first && backlog.truncated,
      );
      first = false;
      page = [];
      bytes = 0;
      return batch;
    }

    for (final entry in backlog.entries) {
      if (page.isNotEmpty &&
          (page.length >= backlogPageLines ||
              bytes + entry.sizeBytes > backlogPageBytes)) {
        yield flush();
      }
      page.add(logEntryToPb(entry));
      bytes += entry.sizeBytes;
    }
    if (page.isNotEmpty || first) yield flush();
  }

  /// Live lines. A client that does not read makes the hub's bounded queue
  /// fill and drop (`dropped` on the next batch).
  @override
  Stream<pb.LogBatch> follow(ServiceCall call, pb.FollowRequest request) {
    _requireInstance(request.instanceId);
    final pressure = call is YaguraCall ? call.pressure : null;
    final hub = daemon.logs.follow(
      request.instanceId,
      sources: request.sources.toSet(),
    );
    StreamSubscription<LogBatch>? source;
    late final StreamController<pb.LogBatch> controller;
    controller = StreamController<pb.LogBatch>(
      sync: true,
      onListen: () {
        source = hub.listen(
          (batch) {
            controller.add(
              pb.LogBatch(
                entries: [for (final e in batch.entries) logEntryToPb(e)],
                dropped: Int64(batch.dropped),
                sourceEvent: batch.sourceEvent,
                source: batch.source,
              ),
            );
            // The transport is full: stop taking lines from the hub, so its
            // own bounded queue drops the oldest and counts them.
            if (pressure != null && pressure.backedUp) {
              source?.pause();
              pressure.whenDrained(() => source?.resume());
            }
          },
          onError: controller.addError,
          onDone: () => unawaited(controller.close()),
        );
      },
      onCancel: () => source?.cancel(),
    );
    return controller.stream;
  }

  void _requireInstance(String id) => daemon.instances.get(id);
}
