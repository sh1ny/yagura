import '../operations/cancel_token.dart';

/// One SteamCMD app run (install, update or validate) into a directory.
class SteamAppRequest {
  const SteamAppRequest({
    required this.appId,
    required this.installDirectory,
    this.validate = false,
    this.account,
  });

  final int appId;
  final String installDirectory;
  final bool validate;

  /// Steam account id, or null for the anonymous login.
  final String? account;
}

/// Where a Steam run reports what it is doing; the operation turns these into
/// step and progress events.
abstract interface class SteamRunReporter {
  /// A new step began (`steam_login`, `download`, ...).
  void step(String name);

  /// Progress of the current step; [percent] is 0-100 or -1 when unknown.
  void progress({double percent = -1, int bytesDone = 0, int bytesTotal = 0});

  void log(String text);
}

/// The Steam service (design D7). Group 6 implements it; tests use a fake.
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
  /// Throws when a stray cannot be terminated.
  Future<void> sweepStrays();
}
