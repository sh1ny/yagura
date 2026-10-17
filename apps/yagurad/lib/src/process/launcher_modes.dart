import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../logs/capture_writer.dart';
import '../logs/log_models.dart';
import '../platform/job_restrictions.dart';
import '../platform/win32.dart';
import '../platform/win32_process.dart';
import 'run_files.dart';

/// Exit codes of the helper modes.
const helperOk = 0;
const helperFailed = 2;
const helperUsage = 64;

/// `yagurad launch --run-dir <dir>` (design D2, ADR 0009): starts the relay in
/// its own hidden console, outside the daemon's job, prints
/// `{relay_pid, relay_created}` as one JSON line and exits. The relay is
/// not a child of anything that will go away.
///
/// Windows only.
Future<int> runLaunchMode(
  String runDirectory,
  StringSink out,
  StringSink err,
) async {
  final self = Platform.resolvedExecutable;
  try {
    final relay = spawnProcess(
      executable: self,
      args: ['relay', '--run-dir', runDirectory],
      flags:
          Win32.createNewConsole |
          Win32.createBreakawayFromJob |
          Win32.createUnicodeEnvironment,
      hidden: true,
    );
    final identity = identityOfHandle(relay.handle, relay.pid);
    Win32.instance.closeHandle(relay.handle);
    out.writeln(
      jsonEncode({'relay_pid': relay.pid, 'relay_created': identity?.created}),
    );
    return helperOk;
  } on SpawnFailure catch (e) {
    // `GetLastError` is not reliable through plain dart:ffi (spike 1.3), so a
    // refused breakaway is named from the job's limits.
    final why = breakawayRestriction();
    err.writeln(
      why == null
          ? '${e.message} (the relay could not be started)'
          : 'the relay could not be started outside the job: $why',
    );
    return helperFailed;
  }
}

/// `yagurad relay --run-dir <dir>`: starts the server on the relay's own
/// console, copies its output to the instance's rotating capture, records its
/// identity and exit, and outlives the daemon.
///
/// Windows only.
Future<int> runRelayMode(String runDirectory, StringSink err) async {
  final win32 = Win32.instance;
  final files = RunFiles(runDirectory);
  final launch = files.readLaunch();
  if (launch == null) {
    err.writeln('relay: $runDirectory has no readable launch.json');
    return helperFailed;
  }

  // Ctrl+C sent to this console is for the server: the relay stays up.
  win32.setConsoleCtrlHandler(nullptr, 0);
  final sigint = ProcessSignal.sigint.watch().listen((_) {});

  final self = identityOfPid(pid);
  if (self == null) {
    await sigint.cancel();
    return helperFailed;
  }
  files.writeRelay(self);
  // The supervisor gave up on this launch before the server was started.
  if (files.isCancelled) {
    files.writeExit(
      -1,
      DateTime.now(),
      error: 'the launch was cancelled before the server was started',
    );
    await sigint.cancel();
    return helperFailed;
  }

  final pipeRead = calloc<IntPtr>();
  final pipeWrite = calloc<IntPtr>();
  final security = calloc<Uint8>(Win32.securityAttributesSize);
  (security).cast<Uint32>().value = Win32.securityAttributesSize;
  (security + 16).cast<Int32>().value = 1;
  final namePointer = 'NUL'.toNativeUtf16();
  var nul = 0;
  SpawnedProcess? server;
  try {
    if (win32.createPipe(pipeRead, pipeWrite, security.cast(), 0) == 0) {
      files.writeExit(-1, DateTime.now(), error: 'CreatePipe failed');
      return helperFailed;
    }
    // The relay's read end must not leak into the server.
    win32.setHandleInformation(pipeRead.value, Win32.handleFlagInherit, 0);
    nul = win32.createFile(
      namePointer,
      Win32.genericRead,
      Win32.fileShareReadWrite,
      security.cast(),
      Win32.openExisting,
      0,
      0,
    );

    try {
      // No console or group flags: the server shares the relay's console, so
      // a Ctrl+C sent to it reaches the server (spike 1.3).
      server = spawnProcess(
        executable: launch.executable,
        args: launch.args,
        workingDirectory: launch.workingDirectory,
        inheritHandles: true,
        stdin: nul == Win32.invalidHandle ? null : nul,
        stdout: pipeWrite.value,
        stderr: pipeWrite.value,
      );
    } on SpawnFailure catch (e) {
      files.writeExit(-1, DateTime.now(), error: e.message);
      return helperFailed;
    } finally {
      win32.closeHandle(pipeWrite.value);
      if (nul != 0 && nul != Win32.invalidHandle) win32.closeHandle(nul);
    }

    final serverIdentity = identityOfHandle(server.handle, server.pid);
    if (serverIdentity == null) {
      files.writeExit(-1, DateTime.now(), error: 'the server vanished');
      return helperFailed;
    }
    files.writeRelayAndServer(self, serverIdentity);
    // The record comes first, then the check: a supervisor that cancels after
    // this check has already seen the server in `relay.json` (or sees it
    // when it looks next) and ends it.
    if (files.isCancelled) {
      win32.terminateProcess(server.handle, 1);
      files.writeExit(
        -1,
        DateTime.now(),
        error: 'the launch was cancelled; the server was ended',
      );
      return helperFailed;
    }

    final capture = CaptureWriter.open(
      CaptureWriter.directoryFor(launch.instanceDirectory),
      encoding: LogEncoding.parse(launch.stdoutEncoding) ?? LogEncoding.utf8,
    );
    try {
      final buffer = calloc<Uint8>(_chunk);
      final available = calloc<Uint32>();
      final read = calloc<Uint32>();
      try {
        void drain() {
          while (true) {
            if (win32.peekNamedPipe(
                  pipeRead.value,
                  nullptr,
                  0,
                  nullptr,
                  available,
                  nullptr,
                ) ==
                0) {
              return;
            }
            if (available.value == 0) return;
            final want = available.value < _chunk ? available.value : _chunk;
            if (win32.readFile(pipeRead.value, buffer, want, read, nullptr) ==
                0) {
              return;
            }
            if (read.value == 0) return;
            capture.write(Uint8List.fromList(buffer.asTypedList(read.value)));
          }
        }

        while (!processEnded(server.handle)) {
          drain();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        // What the server wrote last, and what its children still hold open,
        // is read without waiting for the pipe to close.
        drain();
        files.writeExit(exitCodeOfHandle(server.handle), DateTime.now());
      } finally {
        calloc.free(buffer);
        calloc.free(available);
        calloc.free(read);
      }
    } finally {
      capture.close();
    }
    return helperOk;
  } finally {
    if (server != null) win32.closeHandle(server.handle);
    win32.closeHandle(pipeRead.value);
    calloc.free(pipeRead);
    calloc.free(pipeWrite);
    calloc.free(security);
    calloc.free(namePointer);
    await sigint.cancel();
  }
}

const _chunk = 64 * 1024;

/// `yagurad signal --console-of <pid>`: attaches to the console of [target]
/// and sends it Ctrl+C. Exits non-zero when the console cannot be attached.
/// With [created], the process must have started at that time: a PID that was
/// reused is not signalled. The handle stays open until the signal is sent, so
/// the PID cannot be reused in between.
///
/// Windows only.
Future<int> runSignalMode(int target, {int? created}) async {
  final win32 = Win32.instance;
  var guard = 0;
  if (created != null) {
    guard = win32.openProcess(Win32.processQueryLimitedInformation, 0, target);
    if (guard == 0) return helperFailed;
    if (identityOfHandle(guard, target)?.created != created) {
      win32.closeHandle(guard);
      return helperFailed;
    }
  }
  try {
    win32.freeConsole();
    if (win32.attachConsole(target) == 0) return helperFailed;
    // The helper shares the console it signals, so it ignores the Ctrl+C
    // itself.
    win32.setConsoleCtrlHandler(nullptr, 1);
    final sent = win32.generateConsoleCtrlEvent(0, 0);
    win32.freeConsole();
    return sent == 0 ? helperFailed : helperOk;
  } finally {
    if (guard != 0) win32.closeHandle(guard);
  }
}
