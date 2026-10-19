import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import '../platform/win32.dart';
import '../platform/win32_process.dart';
import '../platform/win32_security.dart';
import 'process_host.dart';

/// What the verifier asks the operating system about processes; a fake
/// answers in tests that must not run real ones.
abstract interface class ProcessTable {
  /// The identity (PID, executable, start time) of the live process [pid].
  ProcessIdentity? identityOf(int pid);

  /// The SID of the user the process [pid] runs as, or null when it cannot be
  /// read (a process of another user may refuse it).
  String? userOf(int pid);

  /// The parent PID the process [pid] was created with (Toolhelp32). A parent
  /// that has ended leaves its PID here.
  int? parentOf(int pid);

  /// Every live process whose parent PID is [pid].
  List<int> childrenOf(int pid);
}

/// The processes of this machine, from Toolhelp32 and the process token.
class WindowsProcessTable implements ProcessTable {
  const WindowsProcessTable();

  @override
  ProcessIdentity? identityOf(int pid) => identityOfPid(pid);

  @override
  String? userOf(int pid) => processUserSid(pid);

  @override
  int? parentOf(int pid) => _snapshot()[pid];

  @override
  List<int> childrenOf(int pid) => [
    for (final entry in _snapshot().entries)
      if (entry.value == pid && entry.key != pid) entry.key,
  ];

  /// PID to parent PID of every process.
  Map<int, int> _snapshot() {
    final win = Win32.instance;
    final parents = <int, int>{};
    final snapshot = win.createToolhelp32Snapshot(Win32.snapProcess, 0);
    if (snapshot == Win32.invalidHandle) return parents;
    final entry = calloc<Uint8>(Win32.processEntrySize);
    try {
      entry.cast<Uint32>().value = Win32.processEntrySize;
      var more = win.process32First(snapshot, entry.cast());
      while (more != 0) {
        // PROCESSENTRY32W: th32ProcessID at 8, th32ParentProcessID at 32.
        parents[(entry + 8).cast<Uint32>().value] = (entry + 32)
            .cast<Uint32>()
            .value;
        more = win.process32Next(snapshot, entry.cast());
      }
    } finally {
      calloc.free(entry);
      win.closeHandle(snapshot);
    }
    return parents;
  }
}

/// The processes Windows starts as children of a console's owner; never a
/// game server.
const _consoleHosts = {'conhost.exe', 'openconsole.exe'};

/// What [ProcessVerifier.verify] found.
sealed class Verification {
  const Verification();
}

/// No live process has the recorded server identity.
class ServerGone extends Verification {
  const ServerGone();
}

/// The server is as the run record says: the relay's child running as the
/// account.
class ServerVerified extends Verification {
  const ServerVerified(this.server);

  final ProcessIdentity server;
}

/// The record named something else; [server] is the relay's own child running
/// as the account, found instead.
class ServerFoundByFallback extends Verification {
  const ServerFoundByFallback(this.server);

  final ProcessIdentity server;
}

/// The record names a process that is not a verified server and the relay has
/// none: nothing is terminated (design D9).
class RecordRejected extends Verification {
  const RecordRejected(this.relay, this.why);

  /// The relay the record names.
  final ProcessIdentity? relay;
  final String why;
}

/// Checks a process against the run record before the daemon signals,
/// terminates or re-attaches it (design D9, ADR 0015). A run file is written
/// by the game-server account, so it proves nothing: the token user, the
/// parentage and the start order do.
class ProcessVerifier {
  ProcessVerifier({
    this.table = const WindowsProcessTable(),
    String? Function()? accountSid,
  }) : _accountSid = accountSid ?? currentUserSid;

  final ProcessTable table;
  final String? Function() _accountSid;

  /// The SID processes must run as: the game-server account's, or the current
  /// user's in dev mode. Null when the account does not exist: no process
  /// runs as it, so none verifies.
  String? get accountSid => _accountSid();

  /// Whether [identity] is a live process with exactly that identity.
  bool _isLive(ProcessIdentity identity) {
    final actual = table.identityOf(identity.pid);
    return actual != null &&
        actual.created == identity.created &&
        sameExecutable(actual.executable, identity.executable);
  }

  /// Whether the process [pid] runs as the account.
  bool runsAsAccount(int pid) {
    final wanted = accountSid;
    final actual = table.userOf(pid);
    return wanted != null &&
        actual != null &&
        actual.toLowerCase() == wanted.toLowerCase();
  }

  /// Whether [identity] is live, has the recorded identity and runs as the
  /// account: a process the daemon may signal or end.
  bool isOurs(ProcessIdentity identity) =>
      _isLive(identity) && runsAsAccount(identity.pid);

  /// Verifies the recorded [server] against the recorded [relay].
  ///
  /// The server is verified when it is live with its recorded identity, runs
  /// as the account, its parent PID is the relay's, and the relay was created
  /// before it. A relay that has ended cannot be asked, so its recorded start
  /// time stands for the start-order check; the account and parent PID are
  /// still checked on the server. Otherwise, when the relay is live and runs
  /// as the account, its own child running as the account is the server.
  Verification verify(ProcessIdentity? server, ProcessIdentity? relay) {
    final relayLive = relay != null && isOurs(relay);
    if (server != null && _isLive(server)) {
      final recordMatches =
          runsAsAccount(server.pid) &&
          relay != null &&
          table.parentOf(server.pid) == relay.pid &&
          relay.created < server.created;
      if (recordMatches) return ServerVerified(server);
      final fallback = relayLive ? _childOf(relay) : null;
      if (fallback != null) return ServerFoundByFallback(fallback);
      return RecordRejected(
        relay,
        'process ${server.pid} is not a child of the relay running as the '
        'game-server account',
      );
    }
    if (server == null && relayLive) {
      final child = _childOf(relay);
      if (child != null) return ServerFoundByFallback(child);
      return const ServerGone();
    }
    return const ServerGone();
  }

  /// The relay a launcher started: its earliest child that runs as the
  /// account, was created after it and runs [executable] (the relay is the
  /// daemon's own executable in `relay` mode), or null. The answer comes from
  /// the operating system, never from a run file.
  ProcessIdentity? relayStartedBy(
    ProcessIdentity launcher, {
    required String executable,
  }) {
    ProcessIdentity? best;
    for (final pid in table.childrenOf(launcher.pid)) {
      final identity = table.identityOf(pid);
      if (identity == null || identity.created <= launcher.created) continue;
      if (!sameExecutable(identity.executable, executable)) continue;
      if (!runsAsAccount(pid)) continue;
      if (best == null || identity.created < best.created) best = identity;
    }
    return best;
  }

  /// The earliest child of [relay] that runs as the account and was created
  /// after it, or null.
  ProcessIdentity? _childOf(ProcessIdentity relay) {
    ProcessIdentity? best;
    for (final pid in table.childrenOf(relay.pid)) {
      final identity = table.identityOf(pid);
      if (identity == null || identity.created <= relay.created) continue;
      // The console host of the relay's console is its child too.
      if (_consoleHosts.contains(
        p.basename(identity.executable).toLowerCase(),
      )) {
        continue;
      }
      if (!runsAsAccount(pid)) continue;
      if (best == null || identity.created < best.created) best = identity;
    }
    return best;
  }
}
