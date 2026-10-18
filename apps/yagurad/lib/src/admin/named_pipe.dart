import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../errors.dart';
import '../platform/win32_pipes.dart';
import '../platform/win32_security.dart';
import 'admin_transport.dart';
import 'admin_wire.dart';

/// Whether the process [serverProcessId] runs as LocalSystem.
typedef ServerVerifier = bool Function(int serverProcessId);

/// Whether this process is an administrator that has not elevated.
typedef ElevationProbe = bool Function();

/// The SID of LocalSystem.
const _localSystemSid = 'S-1-5-18';

/// Buffer of one pipe instance, per direction. A full-size message fits, so
/// a client that sends too much is not stuck in its write when the server
/// refuses the message.
const _pipeBuffer = 128 * 1024;

/// How long a closing server connection waits for the client to take its
/// reply and hang up.
const _drainWait = Duration(seconds: 2);

// Blocking calls run in short-lived isolates so the isolate that owns the
// daemon (or, in tests, both ends of the pipe) keeps running. They take
// only integers and bytes: the handle is process-wide.
Future<bool> _connect(int handle) => Isolate.run(() => connectBlocking(handle));

Future<(FrameStatus, Uint8List)> _readFrame(
  int handle,
  int maxBytes,
  int milliseconds,
) => Isolate.run(() => readFrameBlocking(handle, maxBytes, milliseconds));

Future<void> _writeFrame(int handle, Uint8List frame) =>
    Isolate.run(() => writeBlocking(handle, frame));

Future<void> _drainAndDisconnect(int handle, int milliseconds) =>
    Isolate.run(() {
      waitForPeerClose(handle, milliseconds);
      disconnectAndClose(handle);
    });

Uint8List _frame(Uint8List payload) {
  final frame = Uint8List(4 + payload.length);
  ByteData.sublistView(frame).setUint32(0, payload.length, Endian.little);
  frame.setAll(4, payload);
  return frame;
}

YaguraException _tooLarge(int limit) => YaguraException(
  'message_too_large',
  'an admin message is at most $limit bytes',
  details: {'limit': limit},
);

class _PipeConnection implements AdminConnection {
  _PipeConnection(
    this._handle,
    this._maxBytes, {
    this.serverSide = false,
    this.onClosed,
  });

  final int _handle;
  final int _maxBytes;
  final bool serverSide;
  final void Function()? onClosed;
  var _closed = false;

  @override
  Future<Uint8List> readMessage({required Duration timeout}) async {
    final (status, bytes) = await _readFrame(
      _handle,
      _maxBytes,
      timeout.inMilliseconds,
    );
    switch (status) {
      case FrameStatus.ok:
        return bytes;
      case FrameStatus.tooLarge:
        throw _tooLarge(_maxBytes);
      case FrameStatus.timeout:
        throw YaguraException(
          'admin_request_timeout',
          'no complete message arrived within ${timeout.inMilliseconds} ms',
        );
      case FrameStatus.closed:
        throw YaguraException(
          'admin_connection_closed',
          'the admin channel closed before a message arrived',
        );
    }
  }

  @override
  Future<void> writeMessage(Uint8List payload) async {
    if (payload.length > _maxBytes) throw _tooLarge(_maxBytes);
    try {
      await _writeFrame(_handle, _frame(payload));
    } on Object {
      throw YaguraException(
        'admin_connection_closed',
        'the admin channel closed while a message was written',
      );
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      if (serverSide) {
        await _drainAndDisconnect(_handle, _drainWait.inMilliseconds);
      } else {
        closePipeHandle(_handle);
      }
    } finally {
      onClosed?.call();
    }
  }
}

/// The server end over a Windows named pipe.
///
/// The first instance is created with `FILE_FLAG_FIRST_PIPE_INSTANCE`, so a
/// process that already serves the name makes [open] fail
/// `admin_channel_squatted`. At most [maxClients] instances exist; one waits
/// for the next client while there is room, and a client that finds none
/// free waits (the connector retries) instead of being refused.
class NamedPipeListener implements AdminListener {
  NamedPipeListener({
    this.name = adminPipeName,
    this.sddl = adminPipeSddl,
    this.maxClients = maxAdminClients,
    this.maxMessageBytes = maxAdminMessage,
  });

  final String name;
  final String sddl;
  final int maxClients;
  final int maxMessageBytes;

  final _controller = StreamController<AdminConnection>();
  final _listening = <int>{};
  final _waiting = <Future<void>>[];
  var _instances = 0;
  var _opened = false;
  var _closing = false;

  @override
  Stream<AdminConnection> get connections => _controller.stream;

  @override
  Future<void> open() async {
    final int handle;
    try {
      handle = createPipeInstance(
        name,
        sddl,
        first: true,
        maxInstances: maxClients,
        bufferBytes: _pipeBuffer,
      );
    } on Win32Error catch (e) {
      if (e.code == errorAccessDenied || e.code == errorPipeBusy) {
        throw YaguraException(
          'admin_channel_squatted',
          'another process already serves the admin channel $name; the '
              'daemon does not serve it',
          details: {'pipe': name},
        );
      }
      throw YaguraException(
        'internal_error',
        'cannot create the admin channel $name: $e',
        details: {'pipe': name},
      );
    }
    _opened = true;
    _instances = 1;
    _listen(handle);
  }

  void _listen(int handle) {
    _listening.add(handle);
    late final Future<void> done;
    done = _connect(handle)
        .then((connected) {
          _listening.remove(handle);
          if (_closing || !connected) {
            closePipeHandle(handle);
            _instances--;
            return;
          }
          _controller.add(
            _PipeConnection(
              handle,
              maxMessageBytes,
              serverSide: true,
              onClosed: () {
                _instances--;
                _topUp();
              },
            ),
          );
          _topUp();
        })
        .catchError((Object _) {
          _listening.remove(handle);
          closePipeHandle(handle);
          _instances--;
        })
        .whenComplete(() => _waiting.remove(done));
    _waiting.add(done);
  }

  // Keeps one instance listening while there is room for another client.
  void _topUp() {
    if (_closing || !_opened || _listening.isNotEmpty) return;
    if (_instances >= maxClients) return;
    try {
      final handle = createPipeInstance(
        name,
        sddl,
        first: false,
        maxInstances: maxClients,
        bufferBytes: _pipeBuffer,
      );
      _instances++;
      _listen(handle);
    } on Win32Error {
      // Retried when the next connection closes.
    }
  }

  @override
  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    // A cancel that lands before the blocked call started finds nothing to
    // cancel, so it repeats until every waiting call has returned.
    while (_waiting.isNotEmpty) {
      for (final handle in [..._listening]) {
        cancelPipeIo(handle);
      }
      await Future.any([
        Future.wait([..._waiting]),
        Future<void>.delayed(const Duration(milliseconds: 20)),
      ]);
    }
    // Without a listener the done event is never delivered: do not wait.
    unawaited(_controller.close());
  }
}

/// The client end over a Windows named pipe.
class NamedPipeConnector implements AdminConnector {
  NamedPipeConnector({
    this.name = adminPipeName,
    this.verifier,
    this.elevationMissing,
    this.busyWait = const Duration(seconds: 5),
    this.maxMessageBytes = maxAdminMessage,
    this.onBusy,
  });

  final String name;

  /// Decides whether the server process is trusted; defaults to LocalSystem.
  final ServerVerifier? verifier;

  /// Decides whether a refusal is for want of elevation; defaults to the
  /// token of this process.
  final ElevationProbe? elevationMissing;

  /// How long to wait for a free instance when all are busy.
  final Duration busyWait;
  final int maxMessageBytes;

  /// Called each time every instance was busy and the connector is about to
  /// try again; lets a test wait for the retry instead of for a duration.
  final void Function()? onBusy;

  static bool _isLocalSystem(int pid) => processUserSid(pid) == _localSystemSid;

  @override
  Future<AdminConnection> connect() async {
    final deadline = DateTime.now().add(busyWait);
    while (true) {
      try {
        final handle = openClientPipe(name);
        if (!_trusted(handle)) {
          closePipeHandle(handle);
          throw YaguraException(
            'admin_channel_untrusted',
            'the admin channel $name is not served by the yagura service '
                '(LocalSystem); nothing was sent',
            details: {'pipe': name},
          );
        }
        return _PipeConnection(handle, maxMessageBytes);
      } on Win32Error catch (e) {
        switch (e.code) {
          case errorFileNotFound || errorPathNotFound:
            throw YaguraException(
              'daemon_not_running',
              'the yagura service is not running (nothing serves $name)',
              details: {'pipe': name},
            );
          case errorAccessDenied:
            if ((elevationMissing ?? administratorsAreDenyOnly)()) {
              throw YaguraException(
                'elevation_required',
                'run this command from an elevated prompt (Run as '
                    'administrator)',
              );
            }
            throw YaguraException(
              'access_denied',
              'only an administrator can use the admin channel',
            );
          case errorPipeBusy:
            if (!DateTime.now().isBefore(deadline)) {
              throw YaguraException(
                'admin_channel_busy',
                'the admin channel stayed busy for ${busyWait.inSeconds} s',
              );
            }
            onBusy?.call();
            await Future<void>.delayed(const Duration(milliseconds: 50));
          default:
            throw YaguraException(
              'internal_error',
              'cannot open the admin channel $name: $e',
            );
        }
      }
    }
  }

  bool _trusted(int handle) {
    try {
      return (verifier ?? _isLocalSystem)(serverProcessId(handle));
    } on Win32Error {
      return false;
    }
  }
}
