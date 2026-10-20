import '../operations/cancel_token.dart';
import '../operations/prompt_broker.dart';

/// One SteamCMD app run (install, update or validate) into a directory.
class SteamAppRequest {
  const SteamAppRequest({
    required this.appId,
    required this.installDirectory,
    this.instanceDirectory,
    this.validate = false,
    this.account,
    this.username,
    this.rememberedPassword,
    this.accountRequired = false,
    this.sizeHintBytes,
  });

  final int appId;
  final String installDirectory;

  /// The instance directory [installDirectory] is in, which the files of the
  /// run are confined to (design D8); null confines them to
  /// [installDirectory] itself.
  final String? instanceDirectory;
  final bool validate;

  /// Steam account id, or null for the anonymous login. The run uses the
  /// account's own SteamCMD installation and its cached login (design D2).
  final String? account;

  /// The Steam username of [account].
  final String? username;

  /// The password the daemon remembers for [account], read when the cached
  /// login turned out to be expired; null when it remembers none.
  final String? Function()? rememberedPassword;

  /// The plugin's `steam.login` is `account`: a run without an [account] is
  /// refused with `steam_account_required` before SteamCMD starts.
  final bool accountRequired;

  /// The manifest's `steam.size_hint_bytes`, used for the disk check when the
  /// app's size on this host is not known yet.
  final int? sizeHintBytes;
}

/// Where a Steam run reports what it is doing; the operation turns these into
/// step and progress events.
abstract interface class SteamRunReporter {
  /// A new step began (`steam_login`, `download`, ...).
  void step(String name);

  /// Progress of the current step; [percent] is 0-100 or -1 when unknown.
  void progress({double percent = -1, int bytesDone = 0, int bytesTotal = 0});

  void log(String text);

  /// A warning for the operation's result (`disk_check_skipped`).
  void warn(String warning);

  /// Asks the administrator for input the run needs (a Steam Guard code or a
  /// mobile approval); the operation waits for input until it is resolved.
  PromptTicket prompt(PromptSpec spec);
}

/// A login of a Steam account with its password (design D2): the login step
/// of adding an account or logging it in again.
class SteamLoginRequest {
  const SteamLoginRequest({
    required this.account,
    required this.username,
    required this.password,
  });

  /// The account id, which names its SteamCMD installation.
  final String account;
  final String username;
  final String password;
}

/// The Steam service (design D7). `SteamCmdService` implements it; tests of
/// the other services use a fake.
abstract interface class SteamService {
  /// Runs SteamCMD for [request]. When [cancel] fires it terminates SteamCMD
  /// and throws [OperationCancelled]. Failures throw `YaguraException` with
  /// the Steam reason.
  Future<void> installApp(
    SteamAppRequest request,
    SteamRunReporter reporter,
    CancelToken cancel,
  );

  /// Logs [request]'s account in on its own SteamCMD installation, building
  /// the installation first. Steam Guard is relayed through
  /// [SteamRunReporter.prompt]. On success SteamCMD has cached the login.
  /// Failures throw `YaguraException` with the Steam reason; a cancel throws
  /// [OperationCancelled].
  Future<void> login(
    SteamLoginRequest request,
    SteamRunReporter reporter,
    CancelToken cancel,
  );

  /// Deletes the SteamCMD installation of [account] (its cached login with
  /// it) and forgets that it was ready.
  Future<void> removeInstallation(String account);

  /// Terminates SteamCMD processes left by a previous daemon (design D9).
  /// Throws when a stray cannot be terminated; the installation then stays
  /// unavailable and the service retries the sweep.
  Future<void> sweepStrays();

  /// Stops the service's background work (the sweep retry) and, where it
  /// owns them, ends its SteamCMD processes.
  Future<void> close();
}
