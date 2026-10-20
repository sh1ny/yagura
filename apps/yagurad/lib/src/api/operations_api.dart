import 'dart:async';

import 'package:grpc/grpc.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../errors.dart';
import '../host/daemon.dart';
import '../operations/operations.dart';
import 'convert.dart';
import 'instances_api.dart' show WatchLimits;
import 'pressure.dart';
import 'service_support.dart';

/// The `Operations` service (design D3, D24).
class OperationsApi extends pb.OperationsServiceBase with GuardedService {
  OperationsApi(
    this.daemon,
    this.logSink, {
    this.watchLimits = const WatchLimits(),
  });

  final Daemon daemon;

  /// What may wait for a `WatchOperation` client that does not read.
  final WatchLimits watchLimits;

  @override
  final LogSink logSink;

  /// Largest page `ListOperations` returns.
  static const maxPageSize = 500;
  static const defaultPageSize = 100;

  @override
  Future<pb.Operation> getOperation(
    ServiceCall call,
    pb.GetOperationRequest request,
  ) async {
    final operation = daemon.operations.get(request.operationId);
    if (operation == null) throw _notFound(request.operationId);
    return operationToPb(operation);
  }

  /// Newest first; `page_token` is the offset of the next page.
  @override
  Future<pb.ListOperationsResponse> listOperations(
    ServiceCall call,
    pb.ListOperationsRequest request,
  ) async {
    final size = request.pageSize == 0
        ? defaultPageSize
        : request.pageSize.clamp(1, maxPageSize);
    final offset = int.tryParse(request.pageToken) ?? 0;
    final page = daemon.operations.list(
      instanceId: request.instanceId.isEmpty ? null : request.instanceId,
      limit: size + 1,
      offset: offset,
    );
    return pb.ListOperationsResponse(
      operations: [for (final o in page.take(size)) operationToPb(o)],
      nextPageToken: page.length > size ? '${offset + size}' : '',
    );
  }

  /// Ordered events after `after_sequence`; an operation that was pruned from
  /// history is `operation_expired`.
  @override
  Stream<pb.OperationEvent> watchOperation(
    ServiceCall call,
    pb.WatchOperationRequest request,
  ) {
    final id = request.operationId;
    if (daemon.operations.get(id) == null) {
      throw _wellFormed(id)
          ? YaguraException(
              'operation_expired',
              'operation $id is no longer in the history',
              details: {'operationId': id},
            )
          : _notFound(id);
    }
    final pressure = call is YaguraCall ? call.pressure : null;
    // Events up to here are the replay: a bounded burst the transport takes
    // as fast as the client reads it, which adds to what may wait.
    final replayEnd = daemon.operations.get(id)!.lastSequence;
    var allowedEvents = watchLimits.maxEvents;
    var allowedBytes = watchLimits.maxBytes;
    final source = daemon.operations.watch(
      id,
      afterSequence: request.afterSequence.toInt(),
    );
    if (pressure == null) return source.map(operationEventToPb);
    // Events pile up in the transport for a client that does not read; at the
    // limit they are dropped and the watch ends, so the client resumes from the
    // last event it read (the replay reports what is no longer retained).
    StreamSubscription<OperationEvent>? subscription;
    late final StreamController<pb.OperationEvent> controller;
    controller = StreamController<pb.OperationEvent>(
      sync: true,
      onListen: () {
        subscription = source.listen(
          (event) {
            final out = operationEventToPb(event);
            if (event.sequence <= replayEnd) {
              allowedEvents++;
              allowedBytes += out.writeToBuffer().length + 5;
            } else if (pressure.queuedMessages >= allowedEvents ||
                pressure.queuedBytes >= allowedBytes) {
              pressure.dropQueuedData();
              unawaited(subscription?.cancel());
              controller
                ..addError(
                  YaguraException(
                    'resync_required',
                    'this client reads too slowly; watch again with the '
                        'sequence of the last event it received',
                    details: {'limit': watchLimits.maxEvents},
                  ),
                )
                ..close();
              return;
            }
            controller.add(out);
          },
          onError: controller.addError,
          onDone: () => unawaited(controller.close()),
        );
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<pb.Operation> cancelOperation(
    ServiceCall call,
    pb.CancelOperationRequest request,
  ) async => operationToPb(daemon.operations.cancel(request.operationId));

  /// The first valid answer wins (design D13); the device that sent it is
  /// the one `PromptResolved` names (empty in dev mode).
  @override
  Future<pb.Operation> respondToPrompt(
    ServiceCall call,
    pb.RespondToPromptRequest request,
  ) async {
    final device = daemon.security?.gate.callerOf(call) ?? '';
    return operationToPb(
      daemon.operations.respondToPrompt(
        request.operationId,
        request.promptId,
        request.value,
        device,
      ),
    );
  }

  var _promptSubscribers = 0;

  /// A snapshot of every pending prompt, then each prompt raised and resolved.
  /// A subscriber that falls more than `maxPromptEvents` behind gets
  /// `resync_required` and a new snapshot.
  @override
  Stream<pb.PromptEvent> watchPrompts(
    ServiceCall call,
    pb.WatchPromptsRequest request,
  ) {
    if (_promptSubscribers >= watchLimits.maxSubscribers) {
      throw YaguraException(
        'too_many_subscribers',
        'this daemon already has ${watchLimits.maxSubscribers} prompt '
            'subscribers',
        details: {'limit': watchLimits.maxSubscribers},
      );
    }
    final pressure = call is YaguraCall ? call.pressure : null;
    final broker = daemon.operations.prompts;
    StreamSubscription<PromptBrokerEvent>? source;
    late final StreamController<pb.PromptEvent> controller;

    void sendSnapshot() => controller.add(
      pb.PromptEvent(
        snapshot: pb.PromptSnapshot(
          prompts: [for (final p in broker.snapshot()) pendingPromptToPb(p)],
        ),
      ),
    );

    bool resyncIfBehind() {
      if (pressure == null) return false;
      if (pressure.queuedMessages < watchLimits.maxPromptEvents &&
          pressure.queuedBytes < watchLimits.maxBytes) {
        return false;
      }
      pressure.dropQueuedData();
      controller.add(
        pb.PromptEvent(resyncRequired: pb.PromptsResyncRequired()),
      );
      sendSnapshot();
      return true;
    }

    controller = StreamController<pb.PromptEvent>(
      sync: true,
      onListen: () {
        _promptSubscribers++;
        // Subscribe before reading the snapshot, in the same turn, so no
        // change falls between them.
        source = broker.events.listen((event) {
          if (resyncIfBehind()) return;
          controller.add(switch (event) {
            PromptRaised(:final pending) => pb.PromptEvent(
              raised: pendingPromptToPb(pending),
            ),
            PromptResolved(
              :final promptId,
              :final byDeviceId,
              :final outcome,
            ) =>
              pb.PromptEvent(
                resolved: promptResolvedToPb(promptId, byDeviceId, outcome),
              ),
          });
        }, onDone: () => unawaited(controller.close()));
        sendSnapshot();
      },
      onCancel: () async {
        _promptSubscribers--;
        await source?.cancel();
      },
    );
    return controller.stream;
  }

  /// The daemon's operation ids are `op` and 12 hex digits: a well-formed id
  /// that is not known was pruned, anything else never existed.
  static bool _wellFormed(String id) =>
      RegExp(r'^op[0-9a-f]{12}$').hasMatch(id);

  YaguraException _notFound(String id) => YaguraException(
    'operation_not_found',
    'there is no operation $id',
    details: {'operationId': id},
  );
}
