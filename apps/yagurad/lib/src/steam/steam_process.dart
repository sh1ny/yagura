import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../platform/win32.dart';

/// A running SteamCMD process as the Steam service sees it.
abstract interface class SteamProcess {
  int get pid;

  /// Standard output and error merged, line by line. Ends once the process
  /// ended and its output was read.
  Stream<String> get lines;

  /// Completes with the exit code once the process (and, on Windows, the rest
  /// of its job) is gone.
  Future<int> get exitCode;

  /// Terminates the process and everything it started.
  void kill();
}

/// Starts SteamCMD (design D7, ADR 0010): arguments only, stdin closed, and on
/// Windows inside a kill-on-close job object so that SteamCMD, including the
/// copy it relaunches after a self-update, dies with the daemon.
abstract interface class SteamProcessLauncher {
  /// The launcher for this platform.
  factory SteamProcessLauncher() =>
      Platform.isWindows ? JobObjectLauncher() : PlainProcessLauncher();

  Future<SteamProcess> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    Map<String, String> environment = const {},
  });

  /// Terminates every process this launcher started and still tracks.
  Future<void> close();
}

// ---- portable launcher ------------------------------------------------------

/// Starts processes with `dart:io`; stdin is closed. There is no job object
/// outside Windows: a daemon that dies leaves SteamCMD to the startup sweep.
class PlainProcessLauncher implements SteamProcessLauncher {
  final _live = <_PlainProcess>{};

  @override
  Future<SteamProcess> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    Map<String, String> environment = const {},
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    await process.stdin.close();
    final started = _PlainProcess(process);
    _live.add(started);
    unawaited(started.exitCode.whenComplete(() => _live.remove(started)));
    return started;
  }

  @override
  Future<void> close() async {
    for (final process in List.of(_live)) {
      process.kill();
    }
  }
}

class _PlainProcess implements SteamProcess {
  _PlainProcess(this._process) {
    var open = 2;
    void done() {
      if (--open == 0) _lines.close();
    }

    for (final stream in [_process.stdout, _process.stderr]) {
      stream
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(_lines.add, onDone: done);
    }
  }

  final Process _process;
  final _lines = StreamController<String>();

  @override
  int get pid => _process.pid;

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void kill() {
    if (Platform.isLinux || Platform.isMacOS) {
      // The launcher script runs the real binary as a child.
      Process.run('pkill', ['-KILL', '-P', '${_process.pid}']).ignore();
    }
    _process.kill(ProcessSignal.sigkill);
  }
}

// ---- Windows launcher ------------------------------------------------------

/// Spawns each process suspended, assigns it to a job object that kills its
/// members when the last handle closes, and only then resumes it, so a process
/// it launches in turn cannot escape the job (design D7). stdin is the NUL
/// device; stdout and stderr share one pipe.
class JobObjectLauncher implements SteamProcessLauncher {
  final _live = <_JobProcess>{};

  @override
  Future<SteamProcess> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    Map<String, String> environment = const {},
  }) async {
    final process = _JobProcess.spawn(
      executable,
      arguments,
      workingDirectory,
      environment,
    );
    _live.add(process);
    unawaited(process.exitCode.whenComplete(() => _live.remove(process)));
    return process;
  }

  @override
  Future<void> close() async {
    for (final process in List.of(_live)) {
      process.kill();
    }
  }
}

/// Quotes [argument] for a Windows command line (the `CommandLineToArgvW`
/// rules).
String quoteWindowsArgument(String argument) {
  if (argument.isNotEmpty && !argument.contains(RegExp(r'[\s"]'))) {
    return argument;
  }
  final out = StringBuffer('"');
  var backslashes = 0;
  for (final unit in argument.runes) {
    if (unit == 0x5c) {
      backslashes++;
    } else if (unit == 0x22) {
      out
        ..write(r'\' * (backslashes * 2 + 1))
        ..write('"');
      backslashes = 0;
    } else {
      out
        ..write(r'\' * backslashes)
        ..writeCharCode(unit);
      backslashes = 0;
    }
  }
  out
    ..write(r'\' * (backslashes * 2))
    ..write('"');
  return out.toString();
}

class _JobProcess implements SteamProcess {
  _JobProcess._(this.pid, this._job, this._process, int pipeRead) {
    final output = ReceivePort();
    final decoder = const Utf8Decoder(allowMalformed: true)
        .startChunkedConversion(_LineSink(_lines));
    output.listen((message) {
      if (message is Uint8List) {
        decoder.add(message);
      } else {
        decoder.close();
        output.close();
        _lines.close();
      }
    });
    Isolate.spawn(_readPipe, (output.sendPort, pipeRead));

    final exit = ReceivePort();
    exit.listen((message) {
      exit.close();
      final code = message as int;
      // Closing the job ends anything the process left behind.
      final win = Win32.instance;
      win.closeHandle(_job);
      win.closeHandle(_process);
      _exit.complete(code);
    });
    Isolate.spawn(_waitProcess, (exit.sendPort, _process));
  }

  factory _JobProcess.spawn(
    String executable,
    List<String> arguments,
    String workingDirectory,
    Map<String, String> environment,
  ) {
    final win = Win32.instance;
    final allocated = <Pointer<NativeType>>[];

    var job = 0;
    var processHandle = 0;
    var threadHandle = 0;
    var pipeRead = 0;
    var pipeWrite = 0;
    var nul = 0;
    var succeeded = false;
    try {
      job = win.createJobObject(nullptr, nullptr);
      if (job == 0) throw _lastError('CreateJobObject');
      final limits = calloc<Uint8>(Win32.jobExtendedLimitSize);
      allocated.add(limits);
      (limits + Win32.jobLimitFlagsOffset).cast<Uint32>().value =
          Win32.jobKillOnClose;
      if (win.setInformationJobObject(
            job,
            Win32.jobExtendedLimitInformation,
            limits.cast(),
            Win32.jobExtendedLimitSize,
          ) ==
          0) {
        throw _lastError('SetInformationJobObject');
      }

      final attributes = calloc<Uint8>(Win32.securityAttributesSize);
      allocated.add(attributes);
      attributes.cast<Uint32>().value = Win32.securityAttributesSize;
      (attributes + 16).cast<Int32>().value = 1; // inherit

      final readEnd = calloc<IntPtr>();
      final writeEnd = calloc<IntPtr>();
      allocated
        ..add(readEnd)
        ..add(writeEnd);
      if (win.createPipe(readEnd, writeEnd, attributes.cast(), 0) == 0) {
        throw _lastError('CreatePipe');
      }
      pipeRead = readEnd.value;
      pipeWrite = writeEnd.value;
      // The read end stays ours: it must not be inherited.
      win.setHandleInformation(pipeRead, 1, 0);

      final nulName = 'NUL'.toNativeUtf16();
      allocated.add(nulName);
      nul = win.createFile(
        nulName,
        0x80000000, // GENERIC_READ
        3, // share read and write
        attributes.cast(),
        3, // OPEN_EXISTING
        0,
        0,
      );
      if (nul == Win32.invalidHandle) throw _lastError('CreateFile NUL');

      final startup = calloc<Uint8>(Win32.startupInfoSize);
      allocated.add(startup);
      startup.cast<Uint32>().value = Win32.startupInfoSize;
      (startup + 60).cast<Uint32>().value = Win32.startfUseStdHandles;
      (startup + 80).cast<IntPtr>().value = nul;
      (startup + 88).cast<IntPtr>().value = pipeWrite;
      (startup + 96).cast<IntPtr>().value = pipeWrite;

      final info = calloc<Uint8>(Win32.processInformationSize);
      allocated.add(info);

      final commandLine = [
        executable,
        ...arguments,
      ].map(quoteWindowsArgument).join(' ');
      final application = executable.toNativeUtf16();
      final command = commandLine.toNativeUtf16();
      final directory = workingDirectory.toNativeUtf16();
      final environmentBlock = _environmentBlock({
        ...Platform.environment,
        ...environment,
      });
      allocated
        ..add(application)
        ..add(command)
        ..add(directory)
        ..add(environmentBlock);

      final created = win.createProcess(
        application,
        command,
        nullptr,
        nullptr,
        1, // inherit handles
        Win32.createSuspended |
            Win32.createUnicodeEnvironment |
            Win32.createNoWindow,
        environmentBlock.cast(),
        directory,
        startup.cast(),
        info.cast(),
      );
      if (created == 0) throw _lastError('CreateProcess $executable');
      processHandle = info.cast<IntPtr>().value;
      threadHandle = (info + 8).cast<IntPtr>().value;
      final pid = (info + 16).cast<Uint32>().value;

      // Suspended: nothing it launches can leave the job.
      if (win.assignProcessToJobObject(job, processHandle) == 0) {
        win.terminateProcess(processHandle, 1);
        throw _lastError('AssignProcessToJobObject');
      }
      if (win.resumeThread(threadHandle) == 0xFFFFFFFF) {
        win.terminateProcess(processHandle, 1);
        throw _lastError('ResumeThread');
      }
      win.closeHandle(threadHandle);
      threadHandle = 0;
      // The child holds the write end; ours must close so the pipe ends with
      // the job.
      win.closeHandle(pipeWrite);
      pipeWrite = 0;
      win.closeHandle(nul);
      nul = 0;
      succeeded = true;
      return _JobProcess._(pid, job, processHandle, pipeRead);
    } finally {
      for (final pointer in allocated) {
        calloc.free(pointer);
      }
      if (!succeeded) {
        for (final handle in [threadHandle, pipeWrite, nul, pipeRead, job]) {
          if (handle != 0 && handle != Win32.invalidHandle) {
            win.closeHandle(handle);
          }
        }
        if (processHandle != 0) win.closeHandle(processHandle);
      }
    }
  }

  @override
  final int pid;
  final int _job;
  final int _process;
  final _lines = StreamController<String>();
  final _exit = Completer<int>();

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void kill() {
    if (_exit.isCompleted) return;
    Win32.instance.terminateJobObject(_job, 1);
  }

  static Pointer<Utf16> _environmentBlock(Map<String, String> environment) {
    final units = <int>[];
    for (final entry in environment.entries) {
      units
        ..addAll('${entry.key}=${entry.value}'.codeUnits)
        ..add(0);
    }
    units.add(0);
    final block = calloc<Uint16>(units.length + 1);
    block.asTypedList(units.length).setAll(0, units);
    return block.cast();
  }

  static FileSystemException _lastError(String call) =>
      FileSystemException('$call failed');
}

/// Collects decoded text into whole lines (`\n`, `\r\n` or a lone `\r`, which
/// SteamCMD uses to redraw a progress line).
class _LineSink implements Sink<String> {
  _LineSink(this._target);

  final StreamController<String> _target;
  var _pending = '';

  @override
  void add(String chunk) {
    _pending += chunk;
    var start = 0;
    for (var i = 0; i < _pending.length; i++) {
      final c = _pending.codeUnitAt(i);
      if (c == 0x0a || c == 0x0d) {
        final line = _pending.substring(start, i);
        if (c == 0x0d &&
            i + 1 < _pending.length &&
            _pending.codeUnitAt(i + 1) == 0x0a) {
          i++;
        }
        start = i + 1;
        if (line.isNotEmpty) _target.add(line);
      }
    }
    _pending = _pending.substring(start);
  }

  @override
  void close() {
    if (_pending.isNotEmpty) _target.add(_pending);
    _pending = '';
  }
}

void _readPipe((SendPort, int) arguments) {
  final (port, handle) = arguments;
  final win = Win32.instance;
  final buffer = calloc<Uint8>(4096);
  final read = calloc<Uint32>();
  try {
    while (true) {
      final ok = win.readFile(handle, buffer, 4096, read, nullptr);
      if (ok == 0 || read.value == 0) break;
      port.send(Uint8List.fromList(buffer.asTypedList(read.value)));
    }
  } finally {
    calloc
      ..free(buffer)
      ..free(read);
    win.closeHandle(handle);
    port.send(null);
  }
}

void _waitProcess((SendPort, int) arguments) {
  final (port, handle) = arguments;
  final win = Win32.instance;
  win.waitForSingleObject(handle, 0xFFFFFFFF);
  final code = calloc<Uint32>();
  win.getExitCodeProcess(handle, code);
  final value = code.value;
  calloc.free(code);
  port.send(value);
}
