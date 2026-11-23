import 'dart:async';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../errors.dart';
import '../operations/operations.dart';
import '../platform/disk_space.dart';
import '../steam/steam.dart';
import 'content_store.dart';
import 'workshop_client.dart';

/// Workshop items an operation needs in the content store.
class AcquireRequest {
  const AcquireRequest({
    required this.workshopAppId,
    required this.items,
    this.account,
  });

  /// The app the workshop belongs to (221100 for DayZ).
  final String workshopAppId;
  final List<String> items;

  /// The Steam account to download with; null for the anonymous login.
  final SteamAccountUse? account;
}

/// What became of one requested item.
class AcquiredItem {
  const AcquiredItem({
    required this.item,
    this.version = '',
    this.title = '',
    this.sizeBytes = 0,
    this.path = '',
    this.error,
  });

  final String item;

  /// The published version (`time_updated`); empty when [error] is set.
  final String version;
  final String title;
  final int sizeBytes;

  /// The version directory in the content store.
  final String path;
  final YaguraException? error;

  bool get ok => error == null;
}

/// The outcome of [ContentAcquirer.acquire], per item in request order.
class AcquireResult {
  const AcquireResult(this.items);

  final List<AcquiredItem> items;

  AcquiredItem operator [](String item) =>
      items.firstWhere((i) => i.item == item);

  List<AcquiredItem> get failures => [
    for (final item in items)
      if (!item.ok) item,
  ];

  /// Throws the first failure's reason. Its message names every unavailable
  /// item when that is the reason.
  void throwIfFailed() {
    final bad = failures;
    if (bad.isEmpty) return;
    final first = bad.first.error!;
    if (first.reason == 'workshop_item_unavailable') {
      final ids = [
        for (final f in bad)
          if (f.error!.reason == first.reason) f.item,
      ];
      throw YaguraException(
        first.reason,
        'the workshop items ${ids.join(', ')} do not exist or are private',
        details: {'items': ids},
      );
    }
    throw first;
  }
}

/// One item at one version that some operation waits for. Every operation that
/// needs the same (source, app, item, version) waits on the same flight
/// (design D6).
class _Flight {
  _Flight(this.app, this.item, this.version, this.details);

  final String app;
  final String item;
  String version;
  WorkshopItemDetails details;
  final waiters = <_Waiter>[];
  final done = Completer<AcquiredItem>();

  /// No waiter is left; the item is not published when its run gets there.
  var dropped = false;

  String get key => '$app|$item|$version';
}

/// One acquiring operation.
class _Waiter {
  _Waiter(this.context);

  final OperationContext context;
}

/// One pipeline-owned SteamCMD run (design D6): it holds the installation
/// lock and a heavy slot, owns its cancel token, and reports to every
/// operation that waits on one of its flights.
class _Run {
  _Run(this.id, this.installation, this.flights);

  final String id;
  final String installation;
  final List<_Flight> flights;
  final cancel = CancelToken();

  /// The key of the installation lock: the same as the one an install or
  /// update of an instance takes (`account:<id>`, or `anonymous`).
  String get lockKey =>
      installation == 'anonymous' ? installation : 'account:$installation';

  var position = 0;
  var step = '';
  SteamProgressNote? lastProgress;

  /// The pending prompt of the run, while one is.
  PromptTicket? ticket;

  List<_Waiter> get waiters =>
      <_Waiter>{for (final f in flights) ...f.waiters}.toList();

  void each(void Function(OperationContext context) report) {
    for (final waiter in waiters) {
      try {
        report(waiter.context);
      } on Object {
        // An operation that cannot take the report (ended, runner closed)
        // does not hold the others back.
      }
    }
  }
}

/// The last progress of a run, replayed to an operation that joins late.
class SteamProgressNote {
  const SteamProgressNote(this.percent, this.bytesDone, this.bytesTotal);

  final double percent;
  final int bytesDone;
  final int bytesTotal;
}

/// Acquires workshop items into the content store (design D5, D6).
///
/// An operation asks for items and waits; the downloads run as pipeline-owned
/// SteamCMD runs, not as the operation. A run takes the installation lock and a
/// heavy slot itself, and is cancelled only when no operation waits on any of
/// its items. The operations wait without holding either (step
/// `waiting_for_steamcmd`).
class ContentAcquirer {
  ContentAcquirer({
    required this.runner,
    required this.store,
    required this.workshop,
    required this.steam,
    required this.steamcmdRoot,
    DiskSpaceProbe? diskSpace,
    void Function(String message)? log,
  }) : _diskSpace = diskSpace ?? probeDiskSpace,
       _log = log ?? ((_) {});

  final OperationRunner runner;
  final ContentStore store;
  final WorkshopClient workshop;
  final SteamService steam;

  /// `<data>/steamcmd`: the installations, which hold the download cache.
  final String steamcmdRoot;
  final DiskSpaceProbe _diskSpace;
  final void Function(String message) _log;

  static const _source = ContentStore.workshopSource;
  static final _random = Random.secure();

  /// The flights in progress by key.
  final _flights = <String, _Flight>{};

  /// Reads the versions of [request]'s items, then waits until each is in the
  /// content store or has failed. Unavailable items fail
  /// `workshop_item_unavailable`; a failed item does not fail the others.
  /// Throws only when the metadata cannot be read or [ctx] is cancelled.
  Future<AcquireResult> acquire(
    AcquireRequest request,
    OperationContext ctx,
  ) async {
    ctx.cancel.throwIfCancelled();
    final ids = <String>{...request.items}.toList();
    final details = await _untilCancelled(workshop.details(ids), ctx.cancel);
    ctx.cancel.throwIfCancelled();

    final app = request.workshopAppId;
    final waiter = _Waiter(ctx);
    final outcomes = <String, Future<AcquiredItem>>{};
    final joined = <_Flight>[];
    final created = <_Flight>[];
    for (final id in ids) {
      final d = details[id]!;
      if (!d.available) {
        outcomes[id] = Future.value(
          AcquiredItem(item: id, error: _unavailable(id)),
        );
        continue;
      }
      final published = store.find(_source, app, id, d.version);
      if (published != null) {
        outcomes[id] = Future.value(_acquired(published, d.title));
        continue;
      }
      var flight = _flights['$app|$id|${d.version}'];
      if (flight == null) {
        flight = _Flight(app, id, d.version, d);
        _flights[flight.key] = flight;
        created.add(flight);
      }
      flight.waiters.add(waiter);
      joined.add(flight);
      outcomes[id] = flight.done.future;
    }
    if (created.isNotEmpty) {
      final run = _Run(
        _newRunId(),
        request.account?.id ?? 'anonymous',
        created,
      );
      unawaited(_execute(run, request));
    }
    // An existing run reports to the operation from now on.
    for (final flight in joined) {
      if (!created.contains(flight)) _attach(flight, ctx);
    }

    if (joined.isNotEmpty) {
      final everything = Future.wait([for (final f in joined) f.done.future]);
      final cancelled = ctx.cancel.whenCancelled.then((_) => true);
      final isCancelled = await Future.any([
        everything.then((_) => false),
        cancelled,
      ]);
      if (isCancelled) {
        _detach(waiter, joined);
        throw const OperationCancelled();
      }
    }
    return AcquireResult([for (final id in ids) await outcomes[id]!]);
  }

  /// Tells an operation that joined a running flight where the run is.
  void _attach(_Flight flight, OperationContext ctx) {
    final run = _runOf(flight);
    if (run == null) return;
    try {
      if (run.step.isNotEmpty) ctx.beginStep(run.step);
      if (run.position > 0 && run.step == 'waiting_for_steamcmd') {
        ctx.waiting(run.position);
      }
      if (run.lastProgress case final note?) {
        ctx.progress(
          run.step,
          percent: note.percent,
          bytesDone: note.bytesDone,
          bytesTotal: note.bytesTotal,
        );
      }
      if (run.ticket case final ticket?) ctx.joinPrompt(ticket);
    } on Object catch (e) {
      _log('could not attach ${ctx.operationId} to the run: $e');
    }
  }

  final _runs = <_Flight, _Run>{};

  _Run? _runOf(_Flight flight) => _runs[flight];

  /// An operation left: it stops waiting on [flights]; a flight nobody waits
  /// on is dropped, and a run with no waiting operation is cancelled.
  void _detach(_Waiter waiter, List<_Flight> flights) {
    final affected = <_Run>{};
    for (final flight in flights) {
      flight.waiters.remove(waiter);
      if (_runs[flight] case final run?) affected.add(run);
      if (flight.waiters.isEmpty && !flight.done.isCompleted) {
        flight.dropped = true;
        if (_flights[flight.key] == flight) _flights.remove(flight.key);
      }
    }
    for (final run in affected) {
      if (run.waiters.isEmpty) run.cancel.cancel();
    }
  }

  AcquiredItem _acquired(ContentVersion version, String title) => AcquiredItem(
    item: version.item,
    version: version.version,
    title: title,
    sizeBytes: version.sizeBytes,
    path: version.path,
  );

  YaguraException _unavailable(String id) => YaguraException(
    'workshop_item_unavailable',
    'the workshop item $id does not exist or is private',
    details: {'item': id},
  );

  static String _newRunId() => [
    'run',
    for (var i = 0; i < 12; i++) _random.nextInt(16).toRadixString(16),
  ].join();

  /// [future] or [OperationCancelled] when [cancel] fires first.
  Future<T> _untilCancelled<T>(Future<T> future, CancelToken cancel) {
    final out = Completer<T>();
    future.then(
      (value) {
        if (!out.isCompleted) out.complete(value);
      },
      onError: (Object e, StackTrace s) {
        if (!out.isCompleted) out.completeError(e, s);
      },
    );
    cancel.whenCancelled.then((_) {
      if (!out.isCompleted) out.completeError(const OperationCancelled());
    });
    return out.future;
  }

  // ---- the run -----------------------------------------------------------------

  Future<void> _execute(_Run run, AcquireRequest request) async {
    for (final flight in run.flights) {
      _runs[flight] = run;
    }
    void Function()? release;
    try {
      final reporter = _RunReporter(run);
      // Joining operations learn of the run before it has a lock.
      release = await runner.acquireHeavy(
        installation: run.lockKey,
        cancel: run.cancel,
        onPosition: (position) {
          run.position = position;
          run.step = 'waiting_for_steamcmd';
          run.each((c) => c.waiting(position));
        },
      );
      run.position = 0;
      var pending = _live(run.flights);
      pending = await _checkDisk(run, pending);
      for (var attempt = 1; pending.isNotEmpty; attempt++) {
        run.cancel.throwIfCancelled();
        final results = await steam.downloadWorkshopItems(
          SteamWorkshopRequest(
            workshopAppId: int.parse(request.workshopAppId),
            items: [for (final f in pending) f.item],
            account: request.account?.id,
            username: request.account?.username,
            rememberedPassword: request.account?.rememberedPassword,
          ),
          reporter,
          run.cancel,
        );
        final downloaded = <_Flight>[];
        for (final flight in pending) {
          final result = results
              .where((r) => r.item == flight.item)
              .firstOrNull;
          if (result == null) {
            _fail(
              flight,
              YaguraException(
                'steam_unknown_error',
                'SteamCMD reported nothing for the workshop item '
                    '${flight.item}',
                details: {'item': flight.item},
              ),
            );
          } else if (!result.ok) {
            _fail(flight, result.error!);
          } else {
            downloaded.add(flight);
          }
        }
        final alive = _live(downloaded);
        if (alive.isEmpty) break;
        // The version may have moved while SteamCMD downloaded.
        final fresh = await _untilCancelled(
          workshop.details([for (final f in alive) f.item]),
          run.cancel,
        );
        final changed = <_Flight>[];
        for (final flight in alive) {
          final now = fresh[flight.item]!;
          if (!now.available) {
            _fail(flight, _unavailable(flight.item));
          } else if (now.version != flight.version) {
            _rekey(flight, now);
            if (attempt == 1) {
              changed.add(flight);
            } else {
              _fail(
                flight,
                YaguraException(
                  'workshop_item_changing',
                  'the workshop item ${flight.item} changed again while it '
                      'was downloaded; try again later',
                  details: {'item': flight.item},
                ),
              );
            }
          } else {
            await _publish(run, flight);
          }
        }
        pending = _live(changed);
      }
    } on OperationCancelled {
      _failAll(
        run,
        YaguraException('internal_error', 'the download was cancelled'),
      );
    } on YaguraException catch (e) {
      _failAll(run, e);
    } on Object catch (e) {
      _log('workshop run ${run.id} failed: $e');
      _failAll(run, YaguraException('internal_error', '$e'));
    } finally {
      release?.call();
      _failAll(
        run,
        YaguraException(
          'internal_error',
          'the download ended without a result',
        ),
      );
      for (final flight in run.flights) {
        _runs.remove(flight);
      }
    }
  }

  List<_Flight> _live(Iterable<_Flight> flights) => [
    for (final f in flights)
      if (!f.done.isCompleted && f.waiters.isNotEmpty) f,
  ];

  /// Checks that twice the size of the items so far fits in the free space
  /// before SteamCMD starts; an item that does not fit fails
  /// `insufficient_disk` and the others go on.
  Future<List<_Flight>> _checkDisk(_Run run, List<_Flight> flights) async {
    if (flights.isEmpty) return flights;
    final space = await _diskSpace(steamcmdRoot);
    var total = 0;
    final fits = <_Flight>[];
    for (final flight in flights) {
      final required = 2 * (total + flight.details.sizeBytes);
      if (required > space.freeBytes) {
        _fail(
          flight,
          YaguraException(
            'insufficient_disk',
            'not enough free disk space on ${space.volume} for the workshop '
                'item ${flight.item}: ${space.freeBytes} bytes free, $required '
                'bytes needed (twice the size of the items downloaded so far)',
            details: {
              'volume': space.volume,
              'freeBytes': space.freeBytes,
              'requiredBytes': required,
              'item': flight.item,
            },
          ),
        );
      } else {
        total += flight.details.sizeBytes;
        fits.add(flight);
      }
    }
    return fits;
  }

  /// The flight now stands for the version [now] of its item.
  void _rekey(_Flight flight, WorkshopItemDetails now) {
    if (_flights[flight.key] == flight) _flights.remove(flight.key);
    flight
      ..version = now.version
      ..details = now;
    _flights.putIfAbsent(flight.key, () => flight);
  }

  Future<void> _publish(_Run run, _Flight flight) async {
    if (flight.dropped || flight.waiters.isEmpty) {
      _fail(
        flight,
        YaguraException('internal_error', 'nobody waits for the item'),
      );
      return;
    }
    try {
      final published = await store.publish(
        source: _source,
        app: flight.app,
        item: flight.item,
        version: flight.version,
        fromRoot: p.join(steamcmdRoot, run.installation),
        relative: 'steamapps/workshop/content/${flight.app}/${flight.item}',
        runId: run.id,
      );
      _complete(flight, _acquired(published, flight.details.title));
    } on YaguraException catch (e) {
      _fail(flight, e);
    }
  }

  void _fail(_Flight flight, YaguraException error) =>
      _complete(flight, AcquiredItem(item: flight.item, error: error));

  void _failAll(_Run run, YaguraException error) {
    for (final flight in run.flights) {
      _fail(flight, error);
    }
  }

  void _complete(_Flight flight, AcquiredItem result) {
    if (flight.done.isCompleted) return;
    if (_flights[flight.key] == flight) _flights.remove(flight.key);
    flight.done.complete(result);
  }
}

/// What SteamCMD's run reports, fanned out to the operations that wait on the
/// run's items (design D6).
class _RunReporter implements SteamRunReporter {
  _RunReporter(this._run);

  final _Run _run;

  @override
  void step(String name) {
    _run.step = name;
    _run.each((c) => c.beginStep(name));
  }

  @override
  void progress({double percent = -1, int bytesDone = 0, int bytesTotal = 0}) {
    _run.lastProgress = SteamProgressNote(percent, bytesDone, bytesTotal);
    final step = _run.step;
    _run.each(
      (c) => c.progress(
        step,
        percent: percent,
        bytesDone: bytesDone,
        bytesTotal: bytesTotal,
      ),
    );
  }

  @override
  void log(String text) => _run.each((c) => c.log(text));

  @override
  void warn(String warning) => _run.each((c) => c.warn(warning));

  /// One prompt for the run (design D2, "Prompts in pipeline runs"): raised
  /// through the first waiting operation, joined by the others, and by those
  /// that join later.
  @override
  PromptTicket prompt(PromptSpec spec) {
    PromptTicket? ticket;
    for (final waiter in _run.waiters) {
      try {
        if (ticket == null) {
          ticket = waiter.context.raisePrompt(spec);
        } else {
          waiter.context.joinPrompt(ticket);
        }
      } on OperationCancelled {
        // This operation left; the next one raises it.
      }
    }
    if (ticket == null) throw const OperationCancelled();
    final raised = ticket;
    _run.ticket = raised;
    unawaited(
      raised.result.whenComplete(() {
        if (identical(_run.ticket, raised)) _run.ticket = null;
      }),
    );
    return raised;
  }
}
