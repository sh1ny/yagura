import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import '../platform/win32.dart';

/// A process found running from a SteamCMD directory.
class StrayProcess {
  const StrayProcess(this.pid, this.executable);

  final int pid;
  final String executable;

  @override
  String toString() => '$executable (pid $pid)';
}

/// Finds and ends processes whose executable lies under a directory: the
/// SteamCMD left behind by a daemon that died (design D9). Injectable so a
/// test can make a stray impossible to terminate.
abstract interface class StrayProcessControl {
  /// The platform's implementation.
  factory StrayProcessControl() => _PlatformStrayControl();

  /// Processes whose executable is inside [directory].
  Future<List<StrayProcess>> find(String directory);

  /// Ends [process]; true when it is gone.
  Future<bool> terminate(StrayProcess process);
}

class _PlatformStrayControl implements StrayProcessControl {
  @override
  Future<List<StrayProcess>> find(String directory) async =>
      Platform.isWindows ? _findWindows(directory) : _findLinux(directory);

  @override
  Future<bool> terminate(StrayProcess process) async => Platform.isWindows
      ? _terminateWindows(process)
      : await _terminateLinux(process);

  // ---- Windows --------------------------------------------------------------

  List<StrayProcess> _findWindows(String directory) {
    final win = Win32.instance;
    final found = <StrayProcess>[];
    final snapshot = win.createToolhelp32Snapshot(Win32.snapProcess, 0);
    if (snapshot == Win32.invalidHandle) return found;
    final entry = calloc<Uint8>(Win32.processEntrySize);
    final name = calloc<Uint16>(1040).cast<Utf16>();
    final size = calloc<Uint32>();
    try {
      entry.cast<Uint32>().value = Win32.processEntrySize;
      var more = win.process32First(snapshot, entry.cast());
      while (more != 0) {
        final pid = (entry + 8).cast<Uint32>().value;
        final handle = win.openProcess(
          Win32.processQueryLimitedInformation,
          0,
          pid,
        );
        if (handle != 0) {
          size.value = 520;
          if (win.queryFullProcessImageName(handle, 0, name, size) != 0) {
            final executable = name.toDartString(length: size.value);
            if (p.windows.isWithin(directory, executable)) {
              found.add(StrayProcess(pid, executable));
            }
          }
          win.closeHandle(handle);
        }
        more = win.process32Next(snapshot, entry.cast());
      }
    } finally {
      calloc
        ..free(entry)
        ..free(name)
        ..free(size);
      win.closeHandle(snapshot);
    }
    return found;
  }

  bool _terminateWindows(StrayProcess process) {
    final win = Win32.instance;
    final handle = win.openProcess(
      Win32.processTerminate | Win32.synchronize,
      0,
      process.pid,
    );
    if (handle == 0) return false; // gone already, or not ours to end
    try {
      if (win.terminateProcess(handle, 1) == 0) return false;
      return win.waitForSingleObject(handle, 5000) == Win32.waitObject0;
    } finally {
      win.closeHandle(handle);
    }
  }

  // ---- Linux ----------------------------------------------------------------

  List<StrayProcess> _findLinux(String directory) {
    final found = <StrayProcess>[];
    final proc = Directory('/proc');
    if (!proc.existsSync()) return found;
    for (final entry in proc.listSync(followLinks: false)) {
      final pid = int.tryParse(p.basename(entry.path));
      if (pid == null) continue;
      try {
        final executable = Link(p.join(entry.path, 'exe')).targetSync();
        if (p.isWithin(directory, executable) && !_isZombie(pid)) {
          found.add(StrayProcess(pid, executable));
        }
      } on FileSystemException {
        // Not ours to read, or gone.
      }
    }
    return found;
  }

  bool _isZombie(int pid) {
    try {
      final stat = File('/proc/$pid/stat').readAsStringSync();
      return stat.substring(stat.lastIndexOf(')') + 2).startsWith('Z');
    } on FileSystemException {
      return true;
    }
  }

  Future<bool> _terminateLinux(StrayProcess process) async {
    Process.killPid(process.pid, ProcessSignal.sigkill);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (!Directory('/proc/${process.pid}').existsSync() ||
          _isZombie(process.pid)) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
  }
}
