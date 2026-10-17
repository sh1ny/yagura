import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../process/process_host.dart';
import 'win32.dart';

/// Quotes [argument] for a Windows command line the way the C runtime parses
/// it (backslashes are literal except before a quote).
String quoteWindowsArgument(String argument) {
  if (argument.isNotEmpty && !argument.contains(RegExp(r'[ \t\n\v"]'))) {
    return argument;
  }
  final out = StringBuffer('"');
  var backslashes = 0;
  for (final unit in argument.codeUnits) {
    if (unit == 0x5C) {
      backslashes++;
      continue;
    }
    if (unit == 0x22) {
      // Backslashes before a quote are doubled, and the quote is escaped.
      out
        ..write(r'\' * (backslashes * 2 + 1))
        ..write('"');
    } else {
      out
        ..write(r'\' * backslashes)
        ..writeCharCode(unit);
    }
    backslashes = 0;
  }
  // Backslashes before the closing quote are doubled.
  out
    ..write(r'\' * (backslashes * 2))
    ..write('"');
  return out.toString();
}

/// The command line `CreateProcessW` takes for [executable] and [args].
String windowsCommandLine(String executable, List<String> args) =>
    [executable, ...args].map(quoteWindowsArgument).join(' ');

/// A process created by [spawnProcess]: the thread handle is already closed.
class SpawnedProcess {
  SpawnedProcess(this.pid, this.handle);

  final int pid;

  /// A handle with all access; the owner closes it.
  final int handle;
}

/// Why [spawnProcess] failed: `CreateProcessW` returned 0.
class SpawnFailure implements Exception {
  SpawnFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Starts [executable] with `CreateProcessW`.
///
/// [stdin], [stdout] and [stderr] are inheritable handles for the child's
/// standard handles; when none is given the child gets no standard handles
/// of its own. [environment], when given, is the child's complete
/// environment. Throws [SpawnFailure].
SpawnedProcess spawnProcess({
  required String executable,
  List<String> args = const [],
  String? workingDirectory,
  int flags = 0,
  bool hidden = false,
  bool inheritHandles = false,
  int? stdin,
  int? stdout,
  int? stderr,
  Map<String, String>? environment,
}) {
  final win32 = Win32.instance;
  final commandLine = windowsCommandLine(executable, args).toNativeUtf16();
  final application = executable.toNativeUtf16();
  final cwd = workingDirectory?.toNativeUtf16();
  final info = calloc<Uint8>(Win32.startupInfoSize);
  final processInfo = calloc<Uint8>(Win32.processInformationSize);
  Pointer<Utf16> block = nullptr;
  try {
    info.cast<Uint32>().value = Win32.startupInfoSize;
    var startFlags = 0;
    if (hidden) {
      startFlags |= Win32.startfUseShowWindow;
      (info + 64).cast<Uint16>().value = Win32.swHide;
    }
    if (stdin != null || stdout != null || stderr != null) {
      startFlags |= Win32.startfUseStdHandles;
      (info + 80).cast<IntPtr>().value = stdin ?? 0;
      (info + 88).cast<IntPtr>().value = stdout ?? 0;
      (info + 96).cast<IntPtr>().value = stderr ?? 0;
    }
    (info + 60).cast<Uint32>().value = startFlags;
    var creation = flags;
    if (environment != null) {
      block = _environmentBlock(environment);
      creation |= Win32.createUnicodeEnvironment;
    }
    final ok = win32.createProcess(
      application,
      commandLine,
      nullptr,
      nullptr,
      inheritHandles ? 1 : 0,
      creation,
      block.cast(),
      cwd ?? nullptr,
      info.cast(),
      processInfo.cast(),
    );
    if (ok == 0) throw SpawnFailure('CreateProcessW failed for $executable');
    final process = (processInfo).cast<IntPtr>().value;
    final thread = (processInfo + 8).cast<IntPtr>().value;
    final pid = (processInfo + 16).cast<Uint32>().value;
    win32.closeHandle(thread);
    return SpawnedProcess(pid, process);
  } finally {
    calloc.free(commandLine);
    calloc.free(application);
    if (cwd != null) calloc.free(cwd);
    if (block != nullptr) calloc.free(block);
    calloc.free(info);
    calloc.free(processInfo);
  }
}

Pointer<Utf16> _environmentBlock(Map<String, String> environment) {
  final entries = environment.entries.toList()
    ..sort((a, b) => a.key.toUpperCase().compareTo(b.key.toUpperCase()));
  final text = StringBuffer();
  for (final entry in entries) {
    text
      ..write(entry.key)
      ..write('=')
      ..write(entry.value)
      ..writeCharCode(0);
  }
  text.writeCharCode(0);
  return text.toString().toNativeUtf16();
}

/// The complete environment [overrides] make on top of this process's.
Map<String, String> mergedEnvironment(Map<String, String> overrides) => {
  ...Platform.environment,
  ...overrides,
};

/// The identity (PID, executable, start time) of the live process [pid], or
/// null when there is none or it cannot be inspected.
ProcessIdentity? identityOfPid(int pid) {
  final win32 = Win32.instance;
  final handle = win32.openProcess(
    Win32.processQueryLimitedInformation,
    0,
    pid,
  );
  if (handle == 0) return null;
  try {
    return identityOfHandle(handle, pid);
  } finally {
    win32.closeHandle(handle);
  }
}

/// The identity of the process behind [handle] (query access suffices).
ProcessIdentity? identityOfHandle(int handle, int pid) {
  final win32 = Win32.instance;
  final times = calloc<Uint64>(4);
  final path = calloc<Uint16>(32768).cast<Utf16>();
  final size = calloc<Uint32>()..value = 32768;
  try {
    if (win32.getProcessTimes(handle, times, times + 1, times + 2, times + 3) ==
        0) {
      return null;
    }
    if (win32.queryFullProcessImageName(handle, 0, path, size) == 0) {
      return null;
    }
    return ProcessIdentity(
      pid: pid,
      executable: path.toDartString(length: size.value),
      created: times.value,
    );
  } finally {
    calloc.free(times);
    calloc.free(path);
    calloc.free(size);
  }
}

/// Whether two executable paths name the same file (Windows paths are case
/// insensitive).
bool sameExecutable(String a, String b) =>
    a.replaceAll('/', r'\').toLowerCase() ==
    b.replaceAll('/', r'\').toLowerCase();

/// Whether the process behind [handle] has ended.
bool processEnded(int handle) =>
    Win32.instance.waitForSingleObject(handle, 0) != Win32.waitTimeout;

/// The exit code of the ended process behind [handle], as a signed 32-bit
/// number (`STATUS_CONTROL_C_EXIT` is negative).
int exitCodeOfHandle(int handle) {
  final code = calloc<Uint32>();
  try {
    if (Win32.instance.getExitCodeProcess(handle, code) == 0) return -1;
    return code.value.toSigned(32);
  } finally {
    calloc.free(code);
  }
}
