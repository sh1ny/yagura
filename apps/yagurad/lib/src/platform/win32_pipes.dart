import 'dart:ffi';
import 'dart:io' show sleep;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'win32.dart';
import 'win32_security.dart';

/// The named-pipe calls of the admin channel (design D5), bound by hand with
/// `dart:ffi` like [Win32]. `GetLastError` comes from [Win32], which binds it
/// where a failed call cannot reset it.
///
/// Only touch [instance] on Windows.
class Win32Pipes {
  Win32Pipes._() : this._open(DynamicLibrary.open('kernel32.dll'));

  // Bound at once: binding it after a failed call (lazily) would reset the
  // error it is about to read.
  Win32Pipes._open(this._kernel)
    : lastError = _kernel.lookupFunction<Uint32 Function(), int Function()>(
        'GetLastError',
        isLeaf: true,
      ) {
    // The first call of a binding compiles its stub, which would reset the
    // error a failed call left: do that now.
    lastError();
  }

  final DynamicLibrary _kernel;

  static final Win32Pipes instance = Win32Pipes._();

  late final int Function(
    Pointer<Utf16>,
    int,
    int,
    int,
    int,
    int,
    int,
    Pointer<Void>,
  )
  createNamedPipe = _kernel
      .lookupFunction<
        IntPtr Function(
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Uint32,
          Uint32,
          Uint32,
          Uint32,
          Pointer<Void>,
        ),
        int Function(
          Pointer<Utf16>,
          int,
          int,
          int,
          int,
          int,
          int,
          Pointer<Void>,
        )
      >('CreateNamedPipeW', isLeaf: true);

  // The calls whose error code matters are leaf calls: no safepoint runs
  // between them and `GetLastError`, which could reset the thread's error
  // while other isolates run.
  final int Function() lastError;

  late final int Function(
    Pointer<Utf16>,
    int,
    int,
    Pointer<Void>,
    int,
    int,
    int,
  )
  createFile = _kernel
      .lookupFunction<
        IntPtr Function(
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Pointer<Void>,
          Uint32,
          Uint32,
          IntPtr,
        ),
        int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int)
      >('CreateFileW', isLeaf: true);

  late final int Function(
    int,
    Pointer<Void>,
    int,
    Pointer<Uint32>,
    Pointer<Uint32>,
    Pointer<Uint32>,
  )
  peekNamedPipe = _kernel
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Void>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint32>,
        ),
        int Function(
          int,
          Pointer<Void>,
          int,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint32>,
        )
      >('PeekNamedPipe', isLeaf: true);

  late final int Function(int, Pointer<Void>) connectNamedPipe = _kernel
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Void>),
        int Function(int, Pointer<Void>)
      >('ConnectNamedPipe');

  late final int Function(int, Pointer<Void>) cancelIoEx = _kernel
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Void>),
        int Function(int, Pointer<Void>)
      >('CancelIoEx');

  late final int Function(int) disconnectNamedPipe = _kernel
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'DisconnectNamedPipe',
      );

  late final int Function(
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint32>,
    Pointer<Void>,
  )
  writeFile = _kernel
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Void>,
        ),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
      >('WriteFile');

  late final int Function(int, Pointer<Uint32>) getNamedPipeServerProcessId =
      _kernel.lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint32>),
        int Function(int, Pointer<Uint32>)
      >('GetNamedPipeServerProcessId');

  static const pipeAccessDuplex = 0x3;
  static const fileFlagFirstPipeInstance = 0x00080000;
  static const pipeRejectRemoteClients = 0x8;

  /// `GENERIC_READ | GENERIC_WRITE`.
  static const genericReadWrite = 0xC0000000;

  /// `SECURITY_SQOS_PRESENT | SECURITY_ANONYMOUS`: the server of the pipe
  /// cannot impersonate the client, not even to identify it.
  static const securityAnonymous = 0x00100000;
}

// Win32 error codes the admin channel tells apart.
const errorFileNotFound = 2;
const errorPathNotFound = 3;
const errorAccessDenied = 5;
const errorBrokenPipe = 109;
const errorNoData = 232;
const errorPipeNotConnected = 233;
const errorPipeBusy = 231;
const errorPipeConnected = 535;
const errorOperationAborted = 995;

/// How often a call that failed with error 0 is repeated to read its error.
const _errorReadAttempts = 5;

/// How a blocking read of a frame ended.
enum FrameStatus { ok, timeout, closed, tooLarge }

Win32Error _failed(String call) =>
    Win32Error(call, Win32Pipes.instance.lastError());

/// Creates one instance of the pipe [name] with the descriptor [sddl]. With
/// [first], creation fails (access denied) when the name is taken, which is
/// how a squatter shows. Throws [Win32Error].
int createPipeInstance(
  String name,
  String sddl, {
  required bool first,
  required int maxInstances,
  required int bufferBytes,
}) {
  final pipes = Win32Pipes.instance;
  final text = name.toNativeUtf16();
  try {
    return withSecurityAttributes(sddl, (attributes) {
      // `GetLastError` sometimes reads 0 after the first failure of a call in
      // a process, whatever is done in between (seen under load, with leaf
      // calls and the read in the same function); a repeat of the failed
      // call reads the true code. The calls repeated here have no effect
      // when they fail.
      var handle = Win32.invalidHandle;
      var error = 0;
      for (var attempt = 0; attempt < _errorReadAttempts; attempt++) {
        handle = pipes.createNamedPipe(
          text,
          Win32Pipes.pipeAccessDuplex |
              (first ? Win32Pipes.fileFlagFirstPipeInstance : 0),
          // Byte type and mode, blocking, and no clients from the network.
          Win32Pipes.pipeRejectRemoteClients,
          maxInstances,
          bufferBytes,
          bufferBytes,
          0,
          attributes,
        );
        error = pipes.lastError();
        if (handle != Win32.invalidHandle || error != 0) break;
      }
      if (handle == Win32.invalidHandle) {
        throw Win32Error('CreateNamedPipeW', error);
      }
      return handle;
    });
  } finally {
    calloc.free(text);
  }
}

/// Blocks until a client connects to [handle]. Returns false when the wait
/// was woken by a client that hung up at once, or the client has already gone
/// again.
bool connectBlocking(int handle) {
  final pipes = Win32Pipes.instance;
  if (pipes.connectNamedPipe(handle, nullptr) != 0) return true;
  // Whether it failed because a client connected first
  // (`ERROR_PIPE_CONNECTED`) is told by the pipe, not by the error code,
  // which another isolate's safepoint can reset: a connected instance can be
  // peeked, a listening or cancelled one cannot.
  final available = calloc<Uint32>();
  try {
    return pipes.peekNamedPipe(
          handle,
          nullptr,
          0,
          nullptr,
          available,
          nullptr,
        ) !=
        0;
  } finally {
    calloc.free(available);
  }
}

/// Cancels the blocking call another thread has pending on [handle].
void cancelPipeIo(int handle) {
  Win32Pipes.instance.cancelIoEx(handle, nullptr);
}

void closePipeHandle(int handle) {
  Win32.instance.closeHandle(handle);
}

void disconnectAndClose(int handle) {
  Win32Pipes.instance.disconnectNamedPipe(handle);
  Win32.instance.closeHandle(handle);
}

/// Opens the client end of [name]. Throws [Win32Error] with the code the
/// caller maps (file not found: no server; busy: all instances taken;
/// access denied: the pipe's descriptor refuses this token).
int openClientPipe(String name) {
  final text = name.toNativeUtf16();
  try {
    // See createPipeInstance: a failure that reads as error 0 is repeated.
    var handle = Win32.invalidHandle;
    var error = 0;
    for (var attempt = 0; attempt < _errorReadAttempts; attempt++) {
      handle = Win32Pipes.instance.createFile(
        text,
        Win32Pipes.genericReadWrite,
        0,
        nullptr,
        Win32.openExisting,
        Win32Pipes.securityAnonymous,
        0,
      );
      error = Win32Pipes.instance.lastError();
      if (handle != Win32.invalidHandle || error != 0) break;
    }
    if (handle == Win32.invalidHandle) throw Win32Error('CreateFileW', error);
    return handle;
  } finally {
    calloc.free(text);
  }
}

/// The id of the process serving the pipe behind the client [handle].
int serverProcessId(int handle) {
  final out = calloc<Uint32>();
  try {
    if (Win32Pipes.instance.getNamedPipeServerProcessId(handle, out) == 0) {
      throw _failed('GetNamedPipeServerProcessId');
    }
    return out.value;
  } finally {
    calloc.free(out);
  }
}

/// Bytes waiting in [handle], or -1 when the other end is gone.
int _available(int handle, Pointer<Uint32> out) {
  if (Win32Pipes.instance.peekNamedPipe(
        handle,
        nullptr,
        0,
        nullptr,
        out,
        nullptr,
      ) ==
      0) {
    return -1;
  }
  return out.value;
}

/// Reads exactly [length] bytes, polling so that the deadline holds; the
/// status is [FrameStatus.ok], [FrameStatus.timeout] or [FrameStatus.closed].
(FrameStatus, Uint8List) _readExactly(
  int handle,
  int length,
  DateTime deadline,
) {
  final win32 = Win32.instance;
  final buffer = calloc<Uint8>(length == 0 ? 1 : length);
  final available = calloc<Uint32>();
  final read = calloc<Uint32>();
  try {
    var got = 0;
    while (got < length) {
      final waiting = _available(handle, available);
      if (waiting < 0) return (FrameStatus.closed, Uint8List(0));
      if (waiting == 0) {
        if (!DateTime.now().isBefore(deadline)) {
          return (FrameStatus.timeout, Uint8List(0));
        }
        sleep(const Duration(milliseconds: 2));
        continue;
      }
      final want = waiting < length - got ? waiting : length - got;
      if (win32.readFile(handle, buffer + got, want, read, nullptr) == 0) {
        return (FrameStatus.closed, Uint8List(0));
      }
      got += read.value;
    }
    return (FrameStatus.ok, Uint8List.fromList(buffer.asTypedList(length)));
  } finally {
    calloc
      ..free(buffer)
      ..free(available)
      ..free(read);
  }
}

/// Reads one message: a 4-byte little-endian length, then that many bytes.
/// A length over [maxBytes] ends the read at once, before the body.
(FrameStatus, Uint8List) readFrameBlocking(
  int handle,
  int maxBytes,
  int timeoutMilliseconds,
) {
  final deadline = DateTime.now().add(
    Duration(milliseconds: timeoutMilliseconds),
  );
  final (status, header) = _readExactly(handle, 4, deadline);
  if (status != FrameStatus.ok) return (status, header);
  final length = ByteData.sublistView(header).getUint32(0, Endian.little);
  if (length > maxBytes) return (FrameStatus.tooLarge, Uint8List(0));
  if (length == 0) return (FrameStatus.ok, Uint8List(0));
  return _readExactly(handle, length, deadline);
}

/// Writes [frame] (header included) in full.
void writeBlocking(int handle, Uint8List frame) {
  final buffer = calloc<Uint8>(frame.length);
  final written = calloc<Uint32>();
  try {
    buffer.asTypedList(frame.length).setAll(0, frame);
    var done = 0;
    while (done < frame.length) {
      if (Win32Pipes.instance.writeFile(
            handle,
            buffer + done,
            frame.length - done,
            written,
            nullptr,
          ) ==
          0) {
        throw _failed('WriteFile');
      }
      done += written.value;
    }
  } finally {
    calloc
      ..free(buffer)
      ..free(written);
  }
}

/// Waits until the other end closes, discarding what it still sent. Returns
/// false when [timeoutMilliseconds] ran out first.
bool waitForPeerClose(int handle, int timeoutMilliseconds) {
  final win32 = Win32.instance;
  final deadline = DateTime.now().add(
    Duration(milliseconds: timeoutMilliseconds),
  );
  final available = calloc<Uint32>();
  final read = calloc<Uint32>();
  final scratch = calloc<Uint8>(4096);
  try {
    while (true) {
      final waiting = _available(handle, available);
      if (waiting < 0) return true;
      if (waiting > 0) {
        win32.readFile(
          handle,
          scratch,
          waiting < 4096 ? waiting : 4096,
          read,
          nullptr,
        );
        continue;
      }
      if (!DateTime.now().isBefore(deadline)) return false;
      sleep(const Duration(milliseconds: 2));
    }
  } finally {
    calloc
      ..free(available)
      ..free(read)
      ..free(scratch);
  }
}
