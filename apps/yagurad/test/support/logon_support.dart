import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:yagurad/src/platform/win32.dart';

// Runs a process as another local user without anything that can prompt:
// `CreateProcessWithLogonW` takes the account and password as arguments and
// returns a process handle, so there is no console, UAC or credential dialog
// to wait on, which `Start-Process -Credential` in a PowerShell child is not
// guaranteed to be (it hung the first elevated run of `non_administrator`).

final _advapi = DynamicLibrary.open('advapi32.dll');
final _kernel = DynamicLibrary.open('kernel32.dll');

final int Function(
  Pointer<Utf16>,
  Pointer<Utf16>,
  Pointer<Utf16>,
  int,
  Pointer<Utf16>,
  Pointer<Utf16>,
  int,
  Pointer<Void>,
  Pointer<Utf16>,
  Pointer<Void>,
  Pointer<Void>,
)
_createProcessWithLogon = _advapi
    .lookupFunction<
      Int32 Function(
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Uint32,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Uint32,
        Pointer<Void>,
        Pointer<Utf16>,
        Pointer<Void>,
        Pointer<Void>,
      ),
      int Function(
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        int,
        Pointer<Utf16>,
        Pointer<Utf16>,
        int,
        Pointer<Void>,
        Pointer<Utf16>,
        Pointer<Void>,
        Pointer<Void>,
      )
    >('CreateProcessWithLogonW');

final int Function(int, int) _waitForSingleObject = _kernel
    .lookupFunction<Uint32 Function(IntPtr, Uint32), int Function(int, int)>(
      'WaitForSingleObject',
    );

final int Function(int, Pointer<Uint32>) _getExitCodeProcess = _kernel
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)
    >('GetExitCodeProcess');

final int Function(int, int) _terminateProcess = _kernel
    .lookupFunction<Int32 Function(IntPtr, Uint32), int Function(int, int)>(
      'TerminateProcess',
    );

final int Function(int) _closeHandle = _kernel
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

/// The result of [runAsUser].
class LogonResult {
  const LogonResult({
    required this.started,
    required this.timedOut,
    required this.exitCode,
    required this.pid,
    required this.error,
  });

  /// Whether the process was created; [error] is the Win32 error when not.
  final bool started;
  final bool timedOut;
  final int exitCode;
  final int pid;
  final int error;
}

/// `LOGON_WITH_PROFILE`: the user's profile is loaded (created at the first
/// logon of a new account).
const _logonWithProfile = 1;
const _createNoWindow = 0x08000000;
const _createUnicodeEnvironment = 0x00000400;
const _waitTimeout = 0x102;

/// Runs [commandLine] as the local user [user] with [password], waits up to
/// [timeout] and ends the process when it takes longer. [killTree] is called
/// with the PID of a process that timed out, to end its children too.
///
/// The process has no standard handles: have it redirect its output to a file
/// (`cmd /c "... > out 2>&1"`).
Future<LogonResult> runAsUser({
  required String user,
  required String password,
  required String commandLine,
  required String workingDirectory,
  required Duration timeout,
  required Future<void> Function(int pid) killTree,
}) async {
  final userText = user.toNativeUtf16();
  final domain = '.'.toNativeUtf16();
  final passwordText = password.toNativeUtf16();
  // The command line must be writable memory.
  final command = commandLine.toNativeUtf16();
  final directory = workingDirectory.toNativeUtf16();
  // STARTUPINFOW is 104 bytes (64-bit): only `cb` is set, the rest is zero.
  final startup = calloc<Uint8>(104);
  startup.cast<Uint32>().value = 104;
  // PROCESS_INFORMATION: hProcess, hThread, dwProcessId, dwThreadId.
  final info = calloc<Uint8>(24);
  try {
    // A failed logon has no effect, so a failure that reads as error 0 is
    // repeated (see [callReadingError]).
    final attempt = callReadingError(
      () => _createProcessWithLogon(
        userText,
        domain,
        passwordText,
        _logonWithProfile,
        nullptr,
        command,
        _createNoWindow | _createUnicodeEnvironment,
        nullptr,
        directory,
        startup.cast(),
        info.cast(),
      ),
      (r) => r == 0,
    );
    final created = attempt.value;
    if (created == 0) {
      return LogonResult(
        started: false,
        timedOut: false,
        exitCode: -1,
        pid: 0,
        error: attempt.error,
      );
    }
    final process = info.cast<IntPtr>()[0];
    final thread = info.cast<IntPtr>()[1];
    final pid = (info.cast<Uint32>() + 4).value;
    _closeHandle(thread);
    try {
      final deadline = DateTime.now().add(timeout);
      // Polled, so the event loop (and the test's own timeout) keeps running.
      while (_waitForSingleObject(process, 0) == _waitTimeout) {
        if (DateTime.now().isAfter(deadline)) {
          _terminateProcess(process, 1);
          await killTree(pid);
          return LogonResult(
            started: true,
            timedOut: true,
            exitCode: -1,
            pid: pid,
            error: 0,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      final code = calloc<Uint32>();
      try {
        _getExitCodeProcess(process, code);
        return LogonResult(
          started: true,
          timedOut: false,
          exitCode: code.value,
          pid: pid,
          error: 0,
        );
      } finally {
        calloc.free(code);
      }
    } finally {
      _closeHandle(process);
    }
  } finally {
    calloc
      ..free(userText)
      ..free(domain)
      ..free(passwordText)
      ..free(command)
      ..free(directory)
      ..free(startup)
      ..free(info);
  }
}
