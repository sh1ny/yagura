import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors.dart';
import '../files/files.dart';
import '../host/database.dart';
import '../operations/cancel_token.dart';
import '../operations/semaphore.dart';
import '../platform/disk_space.dart';
import 'steam_patterns.dart';
import 'steam_process.dart';
import 'steam_service.dart';
import 'steam_state.dart';
import 'steamcmd_bootstrap.dart';
import 'stray_processes.dart';

/// What to run for one SteamCMD installation: the executable and the
/// arguments that come before the `+commands`.
class SteamCmdCommand {
  const SteamCmdCommand(this.executable, [this.leadingArguments = const []]);

  final String executable;
  final List<String> leadingArguments;
}

/// How many output lines a failure carries.
const _failureLines = 50;

/// The Steam service for anonymous logins (design D7, ADR 0010).
///
/// One SteamCMD installation lives in `<steamcmdRoot>/anonymous`. Every run is
/// `+command` arguments ending in `+quit` with stdin closed, started through a
/// [SteamProcessLauncher] (suspended, in a kill-on-close job on Windows), and
/// at most one run uses an installation at a time; app runs are keyed by
/// their instance directory and queue on that one lock.
class SteamCmdService implements SteamService {
  SteamCmdService({
    required this.steamcmdRoot,
    SteamCmdBootstrap? bootstrap,
    SteamCmdCommand Function(String installationDirectory)? command,
    SteamProcessLauncher? launcher,
    this.unpackThroughLauncher = false,
    StrayProcessControl? strays,
    DiskSpaceProbe? diskSpace,
    SteamPatterns? patterns,
    SteamState? state,
    this.environment = const {},
    this.noProgressTimeout = const Duration(minutes: 15),
    this.totalTimeout = const Duration(hours: 12),
    this.sweepRetry = const Duration(seconds: 60),
    this.pollInterval = const Duration(seconds: 1),
    void Function(String message)? log,
  }) : _bootstrap = bootstrap ?? SteamCmdBootstrap(),
       _command = command ?? _platformCommand,
       _launcher = launcher ?? SteamProcessLauncher(),
       _strays = strays ?? StrayProcessControl(),
       _diskSpace = diskSpace ?? probeDiskSpace,
       _patterns = patterns ?? SteamPatterns.embedded(),
       _state = state, // ignore: prefer_initializing_formals
       _fs = ConfinedFs(steamcmdRoot),
       _log = log ?? ((message) => stderr.writeln('yagurad: $message'));

  /// The one installation of this version.
  static const anonymousInstallation = 'anonymous';

  /// `<data>/steamcmd`.
  final String steamcmdRoot;
  final Map<String, String> environment;

  /// A step fails after this long without download progress.
  final Duration noProgressTimeout;

  /// A step fails after this long in total.
  final Duration totalTimeout;

  /// How often an unavailable installation is swept again.
  final Duration sweepRetry;

  /// How often a running step is checked against the two caps.
  final Duration pollInterval;

  final SteamCmdBootstrap _bootstrap;
  final SteamCmdCommand Function(String installationDirectory) _command;
  final SteamProcessLauncher _launcher;

  /// Whether the bootstrap unpacks the archive through the launcher, so that
  /// it runs as the SteamCMD account (service mode, design D10).
  final bool unpackThroughLauncher;
  final StrayProcessControl _strays;
  final DiskSpaceProbe _diskSpace;
  final SteamPatterns _patterns;
  SteamState? _state;
  final ConfinedFs _fs;
  final void Function(String message) _log;

  final _locks = <String, Semaphore>{};

  /// Installations a stray SteamCMD blocks, with why.
  final _unavailable = <String, String>{};
  Timer? _retryTimer;
  var _closed = false;

  /// Keeps what the service remembers in [database] from now on, unless a
  /// state was given at construction.
  void useDatabase(YaguraDatabase database, [DateTime Function()? clock]) {
    _state ??= DatabaseSteamState(database, clock);
  }

  SteamState get _remembered => _state ??= MemorySteamState();

  /// The confinement of a run's install directory: the instance directory
  /// when the request names one, else the install directory itself.
  ConfinedFs _confinementFor(SteamAppRequest request) =>
      ConfinedFs(request.instanceDirectory ?? request.installDirectory);

  void _createInstallDirectory(SteamAppRequest request) {
    if (request.instanceDirectory == null) {
      ConfinedFs.create(request.installDirectory);
      return;
    }
    final fs = _confinementFor(request);
    fs.createDirectory(fs.relative(request.installDirectory));
  }

  static SteamCmdCommand _platformCommand(String installationDirectory) =>
      SteamCmdCommand(
        p.join(
          installationDirectory,
          Platform.isWindows ? 'steamcmd.exe' : 'steamcmd.sh',
        ),
      );

  // ---- running an app --------------------------------------------------------

  @override
  Future<void> installApp(
    SteamAppRequest request,
    SteamRunReporter reporter,
    CancelToken cancel,
  ) async {
    if (request.accountRequired || request.account != null) {
      throw YaguraException(
        'steam_account_required',
        'this plugin needs a Steam account, and this version of the daemon '
            'has no Steam accounts',
        details: {'appId': request.appId},
      );
    }
    const installation = anonymousInstallation;
    _requireAvailable(installation);

    final release = await _lockFor(installation).acquire(
      cancel: cancel,
      onPosition: (_) => reporter.step('waiting_for_steamcmd'),
    );
    try {
      _requireAvailable(installation);
      cancel.throwIfCancelled();
      _createInstallDirectory(request);
      await _checkDisk(request, reporter);
      await _ensureBootstrapped(installation, reporter, cancel);
      await _runApp(installation, request, reporter, cancel);
      await _recordSize(request);
    } finally {
      release();
    }
  }

  Semaphore _lockFor(String installation) =>
      _locks.putIfAbsent(installation, () => Semaphore(1));

  void _requireAvailable(String installation) {
    if (_unavailable[installation] case final why?) {
      throw YaguraException(
        'steamcmd_unavailable',
        'the SteamCMD installation "$installation" is unavailable: $why',
        details: {'installation': installation},
      );
    }
  }

  Future<void> _checkDisk(
    SteamAppRequest request,
    SteamRunReporter reporter,
  ) async {
    final known =
        _remembered.lastKnownSize(request.appId) ?? request.sizeHintBytes;
    if (known == null) {
      reporter.warn('disk_check_skipped');
      return;
    }
    final required = known * 2;
    final space = await _diskSpace(request.installDirectory);
    if (space.freeBytes < required) {
      throw YaguraException(
        'insufficient_disk',
        'not enough free space on ${space.volume}: ${space.freeBytes} bytes '
            'free, $required bytes required (twice the $known bytes of app '
            '${request.appId})',
        details: {
          'volume': space.volume,
          'freeBytes': space.freeBytes,
          'requiredBytes': required,
        },
      );
    }
  }

  Future<void> _recordSize(SteamAppRequest request) async {
    final fs = _confinementFor(request);
    final bytes = fs.treeSize(fs.relative(request.installDirectory));
    if (bytes > 0) _remembered.recordSize(request.appId, bytes);
  }

  // ---- bootstrap -------------------------------------------------------------

  Future<void> _ensureBootstrapped(
    String installation,
    SteamRunReporter reporter,
    CancelToken cancel,
  ) async {
    if (_remembered.isReady(installation)) {
      // The ready state is only as good as the directory it describes (ADR
      // 0014): one that is gone, or is not a plain directory, is built again.
      final entry = _fs.stat(installation);
      if (entry != null && entry.isDirectory && !entry.isLink) return;
      _remembered.markNotReady(installation);
    }
    reporter.step('steamcmd_bootstrap');
    try {
      ConfinedFs.create(steamcmdRoot);
      // Whatever an earlier attempt left is not trusted.
      _remembered.markNotReady(installation);
      _fs.deleteTree(installation);
      await _bootstrap.install(
        _fs,
        installation,
        cancel: cancel,
        launcher: unpackThroughLauncher ? _launcher : null,
      );
      cancel.throwIfCancelled();
      // SteamCMD updates itself on its first run, which exits with code 7
      // once the update is installed ("Update complete, launching..."), so
      // its code says nothing. A second run, with nothing left to update,
      // must exit 0 before the installation is marked ready.
      await _execute(
        installation: installation,
        arguments: const ['+quit'],
        anyOutputIsProgress: true,
        reporter: reporter,
        cancel: cancel,
      );
      cancel.throwIfCancelled();
      final outcome = await _execute(
        installation: installation,
        arguments: const ['+quit'],
        anyOutputIsProgress: true,
        reporter: reporter,
        cancel: cancel,
      );
      if (outcome.exitCode != 0) {
        final lines = outcome.tail.toList();
        final lastLines = lines.length > _failureLines
            ? lines.sublist(lines.length - _failureLines)
            : lines;
        throw YaguraException(
          'steamcmd_unavailable',
          'SteamCMD did not run after its self-update: it exited with code '
              '${exitCodeText(outcome.exitCode)}; its last ${lastLines.length} output '
              'lines:\n${lastLines.join('\n')}',
          details: {
            'installation': installation,
            'exitCode': outcome.exitCode,
            'lines': lastLines,
          },
        );
      }
      _remembered.markReady(installation);
    } on Object {
      _remembered.markNotReady(installation);
      try {
        _fs.deleteTree(installation);
      } on Object {
        // Never marked ready, so it is rebuilt next time.
      }
      rethrow;
    }
  }

  // ---- the app run -----------------------------------------------------------

  Future<void> _runApp(
    String installation,
    SteamAppRequest request,
    SteamRunReporter reporter,
    CancelToken cancel,
  ) async {
    var step = 'steam_login';
    reporter.step(step);
    void enter(String next) {
      if (next == step) return;
      step = next;
      reporter.step(next);
    }

    // A known failure marked `retry: once` runs the same command again.
    for (var attempt = 1; ; attempt++) {
      final outcome = await _execute(
        installation: installation,
        arguments: [
          '+force_install_dir',
          request.installDirectory,
          '+login',
          'anonymous',
          '+app_update',
          '${request.appId}',
          if (request.validate) 'validate',
          '+quit',
        ],
        anyOutputIsProgress: false,
        reporter: reporter,
        cancel: cancel,
        onLine: (line) {
          if (_patterns.stepFor(line) case final started?) enter(started);
        },
        onProgress: (progress) {
          enter(progress.step);
          reporter.progress(
            percent: progress.percent,
            bytesDone: progress.bytesDone,
            bytesTotal: progress.bytesTotal,
          );
        },
      );

      final lines = outcome.tail.toList();
      final lastLines = lines.length > _failureLines
          ? lines.sublist(lines.length - _failureLines)
          : lines;
      final failure = _patterns.classify(lines, appId: request.appId);
      if (failure != null && failure.retryOnce && attempt == 1) {
        enter('steam_login');
        continue;
      }
      _judge(request, outcome, failure, lastLines);
      return;
    }
  }

  void _judge(
    SteamAppRequest request,
    _Outcome outcome,
    SteamFailure? known,
    List<String> lastLines,
  ) {
    if (known case final failure?) {
      throw YaguraException(
        failure.reason,
        failure.message,
        details: {
          'appId': request.appId,
          'pattern': failure.id,
          'lines': lastLines,
        },
      );
    }
    if (outcome.exitCode != 0) {
      throw YaguraException(
        'steam_unknown_error',
        'SteamCMD exited with code ${exitCodeText(outcome.exitCode)}; its last '
            '${lastLines.length} output lines:\n${lastLines.join('\n')}',
        details: {
          'appId': request.appId,
          'exitCode': outcome.exitCode,
          'lines': lastLines,
        },
      );
    }
  }

  /// Runs SteamCMD with [arguments] and waits for it, enforcing the two time
  /// caps and cancellation. A step that was cut short throws; anything else
  /// returns the exit code and the end of the output for the caller to judge.
  Future<_Outcome> _execute({
    required String installation,
    required List<String> arguments,
    required bool anyOutputIsProgress,
    required SteamRunReporter reporter,
    required CancelToken cancel,
    void Function(String line)? onLine,
    void Function(SteamProgress progress)? onProgress,
  }) async {
    cancel.throwIfCancelled();
    final directory = p.join(steamcmdRoot, installation);
    final command = _command(directory);
    final SteamProcess process;
    try {
      process = await _launcher.start(
        command.executable,
        [...command.leadingArguments, ...arguments],
        workingDirectory: directory,
        environment: environment,
      );
    } on Object catch (e) {
      // SteamCMD cannot be started: the installation is broken, so the next
      // run builds it again (ADR 0014). An account that cannot be logged on
      // says nothing about the installation.
      if (e is! YaguraException || e.reason != 'launch_logon_failed') {
        _remembered.markNotReady(installation);
      }
      rethrow;
    }

    final tail = Queue<String>();
    final started = DateTime.now();
    var lastProgressAt = started;
    SteamProgress? last;
    String? cutShortBy;
    final linesDone = Completer<void>();

    final subscription = process.lines.listen(
      (line) {
        tail.add(line);
        if (tail.length > 200) tail.removeFirst();
        if (anyOutputIsProgress) lastProgressAt = DateTime.now();
        final progress = _patterns.progressFor(line);
        if (progress == null) {
          reporter.log(line);
          onLine?.call(line);
          return;
        }
        final moved =
            last == null ||
            last!.step != progress.step ||
            last!.bytesDone != progress.bytesDone ||
            last!.bytesTotal != progress.bytesTotal ||
            last!.percent != progress.percent;
        if (moved) lastProgressAt = DateTime.now();
        last = progress;
        onProgress?.call(progress);
      },
      onDone: () {
        if (!linesDone.isCompleted) linesDone.complete();
      },
    );

    void cutShort(String why) {
      if (cutShortBy != null) return;
      cutShortBy = why;
      process.kill();
    }

    final watchdog = Timer.periodic(pollInterval, (_) {
      final now = DateTime.now();
      if (now.difference(started) >= totalTimeout) {
        cutShort('total');
      } else if (now.difference(lastProgressAt) >= noProgressTimeout) {
        cutShort('stalled');
      }
    });
    unawaited(cancel.whenCancelled.then((_) => cutShort('cancelled')));

    final int exitCode;
    try {
      exitCode = await process.exitCode;
      await linesDone.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
    } finally {
      watchdog.cancel();
      await subscription.cancel();
    }

    switch (cutShortBy) {
      case 'cancelled':
        throw const OperationCancelled();
      case 'stalled':
        throw YaguraException(
          'steam_stalled',
          'SteamCMD reported no download progress for '
              '${_describe(noProgressTimeout)} (last progress: '
              '${last == null ? 'none' : '${last!.percent}%, ${last!.bytesDone} of ${last!.bytesTotal} bytes'})',
          details: {
            'limit': 'no_progress',
            'seconds': noProgressTimeout.inSeconds,
            if (last != null) ...{
              'step': last!.step,
              'percent': last!.percent,
              'bytesDone': last!.bytesDone,
              'bytesTotal': last!.bytesTotal,
            },
          },
        );
      case 'total':
        throw YaguraException(
          'steam_stalled',
          'SteamCMD ran for ${_describe(totalTimeout)} in total, which is the '
              'limit',
          details: {'limit': 'total', 'seconds': totalTimeout.inSeconds},
        );
    }
    return _Outcome(exitCode, tail);
  }

  static String _describe(Duration d) => d.inHours >= 1 && d.inMinutes % 60 == 0
      ? '${d.inHours} h'
      : d.inMinutes >= 1 && d.inSeconds % 60 == 0
      ? '${d.inMinutes} min'
      : '${(d.inMilliseconds / 1000).toStringAsFixed(d.inMilliseconds % 1000 == 0 ? 0 : 1)} s';

  // ---- stray sweep -----------------------------------------------------------

  @override
  Future<void> sweepStrays() async {
    if (_fs.stat('') == null) return;
    final blocked = <String>[];
    for (final entry in _fs.list('')) {
      if (!entry.isDirectory) continue;
      final installation = entry.name;
      if (!await _sweep(installation)) blocked.add(installation);
    }
    if (blocked.isNotEmpty) {
      throw YaguraException(
        'steamcmd_unavailable',
        'a SteamCMD process from before this start could not be terminated, '
            'so installation ${blocked.join(', ')} is unavailable until a '
            'sweep succeeds (retried every ${_describe(sweepRetry)})',
        details: {'installations': blocked},
      );
    }
  }

  /// Ends every process running from [installation]. False when one stays;
  /// the installation is then unavailable and swept again later.
  Future<bool> _sweep(String installation) async {
    final directory = p.join(steamcmdRoot, installation);
    final stuck = <StrayProcess>[];
    for (final stray in await _strays.find(directory)) {
      if (await _strays.terminate(stray)) {
        _log('terminated stray SteamCMD process $stray');
      } else {
        stuck.add(stray);
      }
    }
    if (stuck.isEmpty) {
      if (_unavailable.remove(installation) != null) {
        _log('SteamCMD installation "$installation" is available again');
      }
      return true;
    }
    _unavailable[installation] =
        'the process ${stuck.join(', ')} could not be terminated';
    _log(
      'cannot terminate ${stuck.join(', ')}: "$installation" is unavailable',
    );
    _scheduleRetry();
    return false;
  }

  void _scheduleRetry() {
    if (_closed || _retryTimer != null) return;
    _retryTimer = Timer.periodic(sweepRetry, (timer) async {
      for (final installation in _unavailable.keys.toList()) {
        try {
          await _sweep(installation);
        } on Object catch (e) {
          _log('sweep of "$installation" failed: $e');
        }
      }
      if (_unavailable.isEmpty) {
        timer.cancel();
        _retryTimer = null;
      }
    });
  }

  @override
  Future<void> close() async {
    _closed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _launcher.close();
  }
}

class _Outcome {
  _Outcome(this.exitCode, this.tail);

  final int exitCode;
  final Queue<String> tail;
}
