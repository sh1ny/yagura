import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors.dart';
import '../files/files.dart';
import '../host/database.dart';
import '../operations/cancel_token.dart';
import '../operations/prompt_broker.dart';
import '../operations/semaphore.dart';
import '../platform/disk_space.dart';
import 'scrubber.dart';
import 'steam_log_follower.dart';
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
    this.codeWait = const Duration(minutes: 15),
    this.mobileWait = const Duration(minutes: 2),
    this.loginSilence = const Duration(seconds: 60),
    this.loginCap = const Duration(minutes: 10),
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

  /// How long a login waits for an email or authenticator code (design D2).
  final Duration codeWait;

  /// How long a login waits for a mobile approval (design D2).
  final Duration mobileWait;

  /// A login run that neither exits, raises a prompt nor writes to
  /// `console_log.txt` for this long is killed (design D2).
  final Duration loginSilence;

  /// One login run may take this long in total.
  final Duration loginCap;

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
    final account = request.account;
    if (account == null && request.accountRequired) {
      throw YaguraException(
        'steam_account_required',
        'this plugin needs a Steam account: link one to the instance',
        details: {'appId': request.appId},
      );
    }
    if (account != null && (request.username ?? '').isEmpty) {
      throw YaguraException(
        'steam_account_required',
        'the Steam account $account has no username',
        details: {'appId': request.appId},
      );
    }
    final installation = account ?? anonymousInstallation;
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

  // ---- accounts --------------------------------------------------------------

  @override
  Future<void> login(
    SteamLoginRequest request,
    SteamRunReporter reporter,
    CancelToken cancel,
  ) async {
    final installation = request.account;
    _requireAvailable(installation);
    final release = await _lockFor(installation).acquire(
      cancel: cancel,
      onPosition: (_) => reporter.step('waiting_for_steamcmd'),
    );
    try {
      _requireAvailable(installation);
      cancel.throwIfCancelled();
      await _ensureBootstrapped(installation, reporter, cancel);
      await _loginStep(
        installation,
        request.username,
        request.password,
        reporter,
        cancel,
      );
    } finally {
      release();
    }
  }

  @override
  Future<List<SteamWorkshopItemResult>> downloadWorkshopItems(
    SteamWorkshopRequest request,
    SteamRunReporter reporter,
    CancelToken cancel,
  ) async {
    final account = request.account;
    if (account != null && (request.username ?? '').isEmpty) {
      throw YaguraException(
        'steam_account_required',
        'the Steam account $account has no username',
        details: {'appId': request.workshopAppId},
      );
    }
    final installation = account ?? anonymousInstallation;
    _requireAvailable(installation);
    final release = await _lockFor(installation).acquire(
      cancel: cancel,
      onPosition: (_) => reporter.step('waiting_for_steamcmd'),
    );
    try {
      _requireAvailable(installation);
      cancel.throwIfCancelled();
      await _ensureBootstrapped(installation, reporter, cancel);
      return await _runWorkshop(installation, request, reporter, cancel);
    } finally {
      release();
    }
  }

  /// One `+login` and a `+workshop_download_item` per item (design D5). Each
  /// item's own line says how it ended; the run is repeated once after a new
  /// login when the cached one had expired.
  Future<List<SteamWorkshopItemResult>> _runWorkshop(
    String installation,
    SteamWorkshopRequest request,
    SteamRunReporter reporter,
    CancelToken cancel,
  ) async {
    reporter.step('steam_login');
    final account = request.account != null;
    var loggedInAgain = false;
    while (true) {
      final outcomes = <String, WorkshopLine>{};
      var finished = 0;
      void settle(String item, WorkshopLine line) {
        if (outcomes.containsKey(item)) return;
        outcomes[item] = line;
        reporter.progress(percent: ++finished * 100 / request.items.length);
      }

      final outcome = await _execute(
        installation: installation,
        arguments: [
          '+login',
          account ? request.username! : 'anonymous',
          for (final item in request.items) ...[
            '+workshop_download_item',
            '${request.workshopAppId}',
            item,
          ],
          '+quit',
        ],
        anyOutputIsProgress: false,
        reporter: reporter,
        cancel: cancel,
        // Each item's lines are the run's progress: a long run of many items
        // keeps the stall timer fed.
        countsAsProgress: (line) => _patterns.workshopLine(line) != null,
        onLine: (line) {
          switch (_patterns.workshopLine(line)) {
            case WorkshopStarted():
              reporter.step('download');
            case final WorkshopDownloaded done:
              settle(done.item, done);
            case final WorkshopFailed failed:
              settle(failed.item, failed);
            case null:
              break;
          }
        },
      );
      final lines = outcome.tail.toList();
      final lastLines = _lastLines(lines);
      if (account) {
        final login = _patterns.classifyLogin(lines);
        if (login != null && login.kind != LoginKind.ok) {
          if (login.kind == LoginKind.reauthNeeded || login.isGuard) {
            final password = request.rememberedPassword?.call();
            if (password == null || password.isEmpty || loggedInAgain) {
              throw YaguraException(
                'steam_reauth_required',
                'the Steam login of this account has expired; log in again '
                    'with its password',
                details: {'account': request.account},
              );
            }
            loggedInAgain = true;
            await _loginStep(
              installation,
              request.username!,
              password,
              reporter,
              cancel,
            );
            reporter.step('steam_login');
            continue;
          }
          if (login.reason != null) {
            throw YaguraException(
              login.reason!,
              login.message!,
              details: {
                'appId': request.workshopAppId,
                'pattern': login.kind.wire,
              },
            );
          }
        }
      }
      return [
        for (final item in request.items)
          switch (outcomes[item]) {
            WorkshopDownloaded() => SteamWorkshopItemResult(item),
            final WorkshopFailed failed => SteamWorkshopItemResult(
              item,
              YaguraException(
                failed.reason,
                failed.message,
                details: {'item': item, 'appId': request.workshopAppId},
              ),
            ),
            _ => SteamWorkshopItemResult(
              item,
              YaguraException(
                'steam_unknown_error',
                'SteamCMD exited with code ${exitCodeText(outcome.exitCode)} '
                    'without a result for the workshop item $item; its last '
                    '${lastLines.length} output lines:\n${lastLines.join('\n')}',
                details: {
                  'item': item,
                  'appId': request.workshopAppId,
                  'exitCode': outcome.exitCode,
                  'lines': lastLines,
                },
              ),
            ),
          },
      ];
    }
  }

  @override
  Future<void> removeInstallation(String account) async {
    // A run in the installation ends first.
    final release = await _lockFor(account).acquire();
    try {
      _remembered.markNotReady(account);
      _fs.deleteTree(account);
    } finally {
      release();
    }
    _locks.remove(account);
    _unavailable.remove(account);
  }

  /// The login step (design D2): `+login <user> <password>`, and when Steam
  /// asks for a code, one more run with it. A mobile approval is followed
  /// inside the run (see [_loginRun]).
  Future<void> _loginStep(
    String installation,
    String username,
    String password,
    SteamRunReporter reporter,
    CancelToken cancel,
  ) async {
    reporter.step('steam_login');
    final scrubber = Scrubber([password]);
    final first = await _loginRun(
      installation,
      username,
      password,
      null,
      scrubber,
      reporter,
      cancel,
    );
    if (first.kind == LoginKind.ok) return;
    final code = await _askForCode(first.kind, username, reporter, cancel);
    scrubber.add(code);
    final second = await _loginRun(
      installation,
      username,
      password,
      code,
      scrubber,
      reporter,
      cancel,
    );
    if (second.kind != LoginKind.ok) {
      throw _guardInvalid();
    }
  }

  YaguraException _guardInvalid() => YaguraException(
    'steam_guard_invalid',
    'Steam did not accept the Steam Guard code',
  );

  /// Asks for the code Steam sent by email or the authenticator shows, and
  /// waits [codeWait] for it.
  Future<String> _askForCode(
    LoginKind kind,
    String username,
    SteamRunReporter reporter,
    CancelToken cancel,
  ) async {
    final byEmail = kind == LoginKind.guardEmail;
    final ticket = reporter.prompt(
      PromptSpec(
        kind: byEmail ? 'email' : 'authenticator',
        message: byEmail
            ? 'Steam sent a Steam Guard code to the email address of $username. '
                  'Enter it to finish logging in.'
            : 'Enter the code your Steam Guard authenticator shows for '
                  '$username.',
        steamAccount: username,
        wait: codeWait,
      ),
    );
    final result = await Future.any([
      ticket.result,
      cancel.whenCancelled.then(
        (_) => const PromptResult(PromptOutcome.cancelled),
      ),
    ]);
    switch (result.outcome) {
      case PromptOutcome.answered:
        return result.value;
      case PromptOutcome.expired:
        throw YaguraException(
          'steam_guard_timeout',
          'no Steam Guard code was entered within ${_describe(codeWait)}',
        );
      case PromptOutcome.cancelled:
        ticket.close(PromptOutcome.cancelled);
        throw const OperationCancelled();
    }
  }

  /// One `+login` run and what it came to: `ok`, or Steam asking for a code
  /// (`guardEmail`, `guardAuthenticator`). Anything else throws the reason
  /// the output names, or `steam_unknown_error` with the output.
  Future<LoginOutcome> _loginRun(
    String installation,
    String username,
    String password,
    String? code,
    Scrubber scrubber,
    SteamRunReporter reporter,
    CancelToken cancel,
  ) async {
    PromptTicket? mobile;
    _Outcome outcome;
    try {
      outcome = await _execute(
        installation: installation,
        arguments: ['+login', username, password, ?code, '+quit'],
        anyOutputIsProgress: true,
        reporter: reporter,
        cancel: cancel,
        scrubber: scrubber,
        silenceLimit: loginSilence,
        totalLimit: loginCap,
        onGuardMobile: (cutShort) {
          // The run is waiting for the phone: the administrator is told, and
          // the run is ended when nobody confirms in time.
          final ticket = reporter.prompt(
            PromptSpec(
              kind: 'mobile_approval',
              message:
                  'Confirm the login of $username in the Steam Mobile app on '
                  'your phone.',
              steamAccount: username,
              wait: mobileWait,
              acceptsAnswer: false,
            ),
          );
          mobile = ticket;
          unawaited(
            ticket.result.then((result) {
              if (result.outcome == PromptOutcome.expired) {
                cutShort('guard_timeout');
              }
            }),
          );
        },
      );
    } on Object {
      mobile?.close(PromptOutcome.cancelled);
      rethrow;
    }
    final lines = outcome.tail.toList();
    final login = _patterns.classifyLogin(lines);
    // A login that came through ends the wait for the phone.
    final succeeded =
        login?.kind == LoginKind.ok || (login == null && outcome.exitCode == 0);
    mobile?.close(succeeded ? PromptOutcome.answered : PromptOutcome.cancelled);
    if (outcome.cutShort == 'guard_timeout') {
      throw YaguraException(
        'steam_guard_timeout',
        'the login was not confirmed in the Steam Mobile app within '
            '${_describe(mobileWait)}',
      );
    }
    if (succeeded) return const LoginOutcome(LoginKind.ok);
    switch (login?.kind) {
      case LoginKind.guardEmail || LoginKind.guardAuthenticator:
        if (code != null) throw _guardInvalid();
        return login!;
      case LoginKind.reauthNeeded ||
          LoginKind.rateLimited ||
          LoginKind.guardInvalid ||
          LoginKind.loginInvalid:
        throw YaguraException(
          login!.reason!,
          login.message!,
          details: {'pattern': login.kind.wire},
        );
      default:
        // Nothing the table knows, or a mobile approval that ended without
        // a login: SteamCMD's own words.
        throw _unknownError(outcome, _lastLines(lines));
    }
  }

  List<String> _lastLines(List<String> lines) => lines.length > _failureLines
      ? lines.sublist(lines.length - _failureLines)
      : lines;

  YaguraException _unknownError(_Outcome outcome, List<String> lastLines) =>
      YaguraException(
        'steam_unknown_error',
        'SteamCMD exited with code ${exitCodeText(outcome.exitCode)}; its last '
            '${lastLines.length} output lines:\n${lastLines.join('\n')}',
        details: {'exitCode': outcome.exitCode, 'lines': lastLines},
      );

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

    final account = request.account != null;
    var attempt = 1;
    var loggedInAgain = false;
    while (true) {
      final outcome = await _execute(
        installation: installation,
        arguments: [
          '+force_install_dir',
          request.installDirectory,
          '+login',
          account ? request.username! : 'anonymous',
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
      final lastLines = _lastLines(lines);
      if (account) {
        final login = _patterns.classifyLogin(lines);
        if (login != null && login.kind != LoginKind.ok) {
          if (login.kind == LoginKind.reauthNeeded || login.isGuard) {
            // The cached login is gone. With the password remembered, log in
            // again (Steam Guard may ask) and run the app once more.
            final password = request.rememberedPassword?.call();
            if (password == null || password.isEmpty || loggedInAgain) {
              throw YaguraException(
                'steam_reauth_required',
                'the Steam login of this account has expired; log in again '
                    'with its password',
                details: {'account': request.account},
              );
            }
            loggedInAgain = true;
            await _loginStep(
              installation,
              request.username!,
              password,
              reporter,
              cancel,
            );
            enter('steam_login');
            continue;
          }
          if (login.reason != null) {
            throw YaguraException(
              login.reason!,
              login.message!,
              details: {'appId': request.appId, 'pattern': login.kind.wire},
            );
          }
        }
      }
      final failure = _patterns.classify(lines, appId: request.appId);
      // A known failure marked `retry: once` runs the same command again.
      if (failure != null && failure.retryOnce && attempt == 1) {
        attempt++;
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

  /// Runs SteamCMD with [arguments] and waits for it, enforcing the time caps
  /// and cancellation. A step that was cut short throws; anything else
  /// returns the exit code and the end of the output for the caller to judge.
  ///
  /// SteamCMD's stdout reaches the daemon only when it exits, but its
  /// `logs/console_log.txt` is written as it goes (design D15): the run
  /// follows that file, and its progress lines drive the reporter and the
  /// stall timer. Stdout is the fallback where no log is written. Every line
  /// goes through [scrubber] first.
  ///
  /// With [silenceLimit] the run is also cut short, as `silent`, when it
  /// neither exits nor writes a line for that long, unless the login waits for
  /// a mobile approval. [onGuardMobile] is called, once, when the connection
  /// log says it does; it gets the function that cuts the run short. A reason
  /// it passes comes back as [_Outcome.cutShort].
  Future<_Outcome> _execute({
    required String installation,
    required List<String> arguments,
    required bool anyOutputIsProgress,
    required SteamRunReporter reporter,
    required CancelToken cancel,
    Scrubber? scrubber,
    Duration? silenceLimit,
    Duration? totalLimit,
    void Function(void Function(String why) cutShort)? onGuardMobile,
    void Function(String line)? onLine,
    void Function(SteamProgress progress)? onProgress,
    bool Function(String line)? countsAsProgress,
  }) async {
    cancel.throwIfCancelled();
    final directory = p.join(steamcmdRoot, installation);
    final command = _command(directory);
    final scrub = scrubber ?? Scrubber.none;
    final tail = Queue<String>();
    final started = DateTime.now();
    var lastProgressAt = started;
    var lastSignalAt = started;
    SteamProgress? last;
    String? cutShortBy;
    var followed = false;
    var guardSeen = false;

    void report(SteamProgress progress) {
      final moved =
          last == null ||
          last!.step != progress.step ||
          last!.bytesDone != progress.bytesDone ||
          last!.bytesTotal != progress.bytesTotal ||
          last!.percent != progress.percent;
      if (moved) lastProgressAt = DateTime.now();
      last = progress;
      onProgress?.call(progress);
    }

    SteamProcess? running;
    void cutShort(String why) {
      if (cutShortBy != null) return;
      cutShortBy = why;
      running?.kill();
    }

    final installationFs = ConfinedFs(directory);
    final console = SteamLogFollower(
      fs: installationFs,
      path: _consoleLog,
      scrubber: scrub,
      stripTimestamp: true,
      onLine: (line) {
        followed = true;
        lastSignalAt = DateTime.now();
        if (anyOutputIsProgress || (countsAsProgress?.call(line) ?? false)) {
          lastProgressAt = lastSignalAt;
        }
        if (_patterns.progressFor(line) case final progress?) {
          report(progress);
        } else {
          onLine?.call(line);
        }
      },
    );
    final connection = onGuardMobile == null
        ? null
        : SteamLogFollower(
            fs: installationFs,
            path: _patterns.connectionLog,
            scrubber: scrub,
            stripTimestamp: true,
            onLine: (line) {
              if (guardSeen || !_patterns.isLiveGuardMobile(line)) return;
              guardSeen = true;
              onGuardMobile(cutShort);
            },
          );
    // Where the logs stand now, before SteamCMD can write to them.
    console.start();
    connection?.start();

    final SteamProcess process;
    try {
      process = await _launcher.start(
        command.executable,
        [...command.leadingArguments, ...arguments],
        workingDirectory: directory,
        environment: environment,
      );
    } on Object catch (e) {
      console.stop();
      connection?.stop();
      // SteamCMD cannot be started: the installation is broken, so the next
      // run builds it again (ADR 0014). An account that cannot be logged on
      // says nothing about the installation.
      if (e is! YaguraException || e.reason != 'launch_logon_failed') {
        _remembered.markNotReady(installation);
      }
      rethrow;
    }
    running = process;
    final linesDone = Completer<void>();

    final subscription = process.lines.listen(
      (raw) {
        // The log may already hold what stdout now repeats.
        if (!followed) console.poll();
        final line = scrub.scrub(raw);
        tail.add(line);
        if (tail.length > 200) tail.removeFirst();
        lastSignalAt = DateTime.now();
        if (anyOutputIsProgress || (countsAsProgress?.call(line) ?? false)) {
          lastProgressAt = lastSignalAt;
        }
        final progress = _patterns.progressFor(line);
        if (progress == null) {
          reporter.log(line);
          if (!followed) onLine?.call(line);
          return;
        }
        if (!followed) report(progress);
      },
      onDone: () {
        if (!linesDone.isCompleted) linesDone.complete();
      },
    );

    final cap = totalLimit ?? totalTimeout;
    final watchdog = Timer.periodic(pollInterval, (_) {
      final now = DateTime.now();
      if (now.difference(started) >= cap) {
        cutShort('total');
      } else if (now.difference(lastProgressAt) >= noProgressTimeout) {
        cutShort('stalled');
      } else if (silenceLimit != null &&
          !guardSeen &&
          now.difference(lastSignalAt) >= silenceLimit) {
        cutShort('silent');
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
      console.stop();
      connection?.stop();
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
          'SteamCMD ran for ${_describe(cap)} in total, which is the '
              'limit',
          details: {'limit': 'total', 'seconds': cap.inSeconds},
        );
      case 'silent':
        final shown = console.lastLines;
        throw YaguraException(
          'steam_login_unresponsive',
          'SteamCMD did not answer for ${_describe(silenceLimit!)} while '
              'logging in; the last lines of its console log:\n'
              '${shown.isEmpty ? '(it wrote none)' : shown.join('\n')}',
          details: {'seconds': silenceLimit.inSeconds, 'lines': shown},
        );
    }
    return _Outcome(exitCode, tail, cutShort: cutShortBy);
  }

  /// SteamCMD's console log below its installation.
  static const _consoleLog = 'logs/console_log.txt';

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
  _Outcome(this.exitCode, this.tail, {this.cutShort});

  final int exitCode;
  final Queue<String> tail;

  /// Why the run was ended by a callback, when it was.
  final String? cutShort;
}
