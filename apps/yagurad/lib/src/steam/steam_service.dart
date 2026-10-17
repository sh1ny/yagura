import '../operations/cancel_token.dart';

/// One SteamCMD app run (install, update or validate) into a directory.
class SteamAppRequest {
  const SteamAppRequest({
    required this.appId,
    required this.installDirectory,
    this.validate = false,
    this.account,
    this.accountRequired = false,
    this.sizeHintBytes,
  });

  final int appId;
  final String installDirectory;
  final bool validate;

  /// Steam account id, or null for the anonymous login.
  final String? account;

  /// The plugin's `steam.login` is `account`: this version has no Steam
  /// accounts, so the run is refused with `steam_account_required` before
  /// SteamCMD starts.
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

  /// Terminates SteamCMD processes left by a previous daemon (design D9).
  /// Throws when a stray cannot be terminated; the installation then stays
  /// unavailable and the service retries the sweep.
  Future<void> sweepStrays();

  /// Stops the service's background work (the sweep retry) and, where it
  /// owns them, ends its SteamCMD processes.
  Future<void> close();
}
