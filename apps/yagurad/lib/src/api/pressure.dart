// package:grpc builds its server on a handler class it does not export, and
// the handler never pauses a response stream whose client stopped reading
// (the data piles up inside package:http2 where nothing can see or drop it).
// The daemon needs to see that (design D15, log follow), so it subclasses the
// handler and the server here.
// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:grpc/src/server/handler.dart';
import 'package:http2/transport.dart';

import 'api_error.dart';

/// Largest request message the daemon reads (`docs/protocol.md`).
const maxRequestBytes = 4 * 1024 * 1024;

/// Largest response message the daemon sends.
const maxResponseBytes = 16 * 1024 * 1024;

/// Wraps the outgoing side of one HTTP/2 stream so the daemon can see when
/// the client is not reading it, count what is waiting, and drop it.
///
/// While the transport accepts data, messages pass straight through. When
/// HTTP/2 flow control stops reading (the client does not read), messages
/// wait here, where [queuedMessages] and [queuedBytes] count them and
/// [dropQueuedData] can discard them.
///
/// It also enforces the message size limits: a request whose gRPC frame
/// announces more than [maxRequestBytes] is refused before it is read, and a
/// response above [maxResponseBytes] ends the call `RESOURCE_EXHAUSTED`.
class PressureStream extends ServerTransportStream {
  PressureStream(
    this._inner, {
    this.requestLimit = maxRequestBytes,
    this.responseLimit = maxResponseBytes,
  }) {
    _out = StreamController<StreamMessage>(
      onPause: () => _transportPaused = true,
      onResume: () {
        _transportPaused = false;
        _drain();
      },
    );
    _sink = _PressureSink(this);
    _forwarding = _inner.outgoingMessages.addStream(_out.stream);
  }

  final ServerTransportStream _inner;
  final int requestLimit;
  final int responseLimit;
  late final StreamController<StreamMessage> _out;
  late final _PressureSink _sink;
  late final Future<void> _forwarding;
  final _queue = Queue<StreamMessage>();
  final _drainListeners = <void Function()>[];
  var _transportPaused = false;
  var _closeRequested = false;
  var _closed = false;
  var _queuedBytes = 0;
  var _queuedMessages = 0;
  var _headersSent = false;
  var _rejected = false;

  // gRPC frame scanner of the request side: the 5 header bytes (flag, length)
  // collected so far, and the body bytes still to skip.
  final _frameHeader = <int>[];
  var _frameRemaining = 0;

  /// Data messages waiting for the client to read.
  int get queuedMessages => _queuedMessages;

  /// Bytes of those messages, with their gRPC framing.
  int get queuedBytes => _queuedBytes;

  /// The client is not keeping up: something is waiting or HTTP/2 flow
  /// control has stopped the stream.
  bool get backedUp => _transportPaused || _queue.isNotEmpty;

  /// Calls [listener] once the transport accepts data again and nothing is
  /// waiting.
  void whenDrained(void Function() listener) {
    if (!backedUp) {
      listener();
    } else {
      _drainListeners.add(listener);
    }
  }

  /// Discards the data messages that wait (headers and trailers stay) and
  /// returns how many there were.
  int dropQueuedData() {
    final before = _queue.length;
    _queue.removeWhere((m) => m is DataStreamMessage && !m.endStream);
    _queuedMessages = 0;
    _queuedBytes = 0;
    return before - _queue.length;
  }

  void _add(StreamMessage message) {
    if (_closed || _rejected) return;
    if (message is HeadersStreamMessage) _headersSent = true;
    if (message is DataStreamMessage &&
        message.bytes.length > responseLimit + 5) {
      _reject(
        grpcErrorFor(
          'message_too_large',
          'a response of ${message.bytes.length - 5} bytes exceeds the '
              '$responseLimit byte limit',
          metadata: {'limit': '$responseLimit'},
        ),
      );
      return;
    }
    if (!_transportPaused && _queue.isEmpty) {
      _out.add(message);
      return;
    }
    _queue.add(message);
    if (message is DataStreamMessage) {
      _queuedMessages++;
      _queuedBytes += message.bytes.length;
    }
  }

  /// Ends the call with [error]; later writes are ignored.
  void _reject(GrpcError error) {
    final headers = [
      if (!_headersSent) ...[
        Header.ascii(':status', '200'),
        Header.ascii('content-type', 'application/grpc'),
      ],
      Header.ascii('grpc-status', '${error.code}'),
      Header.ascii(
        'grpc-message',
        Uri.encodeFull(error.message ?? '').replaceAll('%20', ' '),
      ),
      for (final MapEntry(:key, :value) in error.trailers!.entries)
        Header.ascii(key, value),
    ];
    final trailers = HeadersStreamMessage(headers, endStream: true);
    _headersSent = true;
    if (!_transportPaused && _queue.isEmpty) {
      _out.add(trailers);
    } else {
      _queue.add(trailers);
    }
    _rejected = true;
    _closeRequested = true;
    if (_queue.isEmpty && !_transportPaused) unawaited(_finish());
  }

  /// Looks at request bytes for a frame that announces too large a message;
  /// returns its announced length, or null.
  int? _oversizedFrame(List<int> bytes) {
    var i = 0;
    while (i < bytes.length) {
      if (_frameRemaining > 0) {
        final take = _frameRemaining < bytes.length - i
            ? _frameRemaining
            : bytes.length - i;
        _frameRemaining -= take;
        i += take;
        continue;
      }
      _frameHeader.add(bytes[i++]);
      if (_frameHeader.length == 5) {
        final length =
            (_frameHeader[1] << 24) |
            (_frameHeader[2] << 16) |
            (_frameHeader[3] << 8) |
            _frameHeader[4];
        _frameHeader.clear();
        if (length > requestLimit) return length;
        _frameRemaining = length;
      }
    }
    return null;
  }

  late final Stream<StreamMessage> _incoming = _inner.incomingMessages
      .transform(
        StreamTransformer<StreamMessage, StreamMessage>.fromHandlers(
          handleData: (message, sink) {
            if (_rejected) return;
            if (message is DataStreamMessage) {
              if (_oversizedFrame(message.bytes) case final length?) {
                _reject(
                  grpcErrorFor(
                    'message_too_large',
                    'a request of $length bytes exceeds the $requestLimit '
                        'byte limit',
                    metadata: {'limit': '$requestLimit'},
                  ),
                );
                return;
              }
            }
            sink.add(message);
          },
        ),
      );

  void _drain() {
    while (!_transportPaused && _queue.isNotEmpty && !_closed) {
      final message = _queue.removeFirst();
      if (message is DataStreamMessage && !message.endStream) {
        _queuedMessages--;
        _queuedBytes -= message.bytes.length;
      }
      _out.add(message);
    }
    if (_queue.isEmpty && !_transportPaused) {
      final listeners = List.of(_drainListeners);
      _drainListeners.clear();
      for (final listener in listeners) {
        listener();
      }
      if (_closeRequested) unawaited(_finish());
    }
  }

  Future<void> _close() async {
    _closeRequested = true;
    if (_queue.isEmpty && !_transportPaused) await _finish();
  }

  Future<void> _finish() async {
    if (_closed) return;
    _closed = true;
    await _out.close();
    await _forwarding.catchError((Object _) {});
    await _inner.outgoingMessages.close();
  }

  @override
  int get id => _inner.id;

  @override
  Stream<StreamMessage> get incomingMessages => _incoming;

  @override
  StreamSink<StreamMessage> get outgoingMessages => _sink;

  @override
  set onTerminated(void Function(int?) value) => _inner.onTerminated = (code) {
    // The client reset the stream: nothing may be written to it any more.
    _closed = true;
    _queue.clear();
    _queuedMessages = 0;
    _queuedBytes = 0;
    value(code);
  };

  @override
  void terminate() {
    _queue.clear();
    _queuedMessages = 0;
    _queuedBytes = 0;
    _closed = true;
    _inner.terminate();
  }

  @override
  bool get canPush => _inner.canPush;

  @override
  ServerTransportStream push(List<Header> requestHeaders) =>
      _inner.push(requestHeaders);
}

class _PressureSink implements StreamSink<StreamMessage> {
  _PressureSink(this._stream);

  final PressureStream _stream;

  @override
  void add(StreamMessage event) => _stream._add(event);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    // Nothing writes errors here; a failed stream ends in terminate().
  }

  @override
  Future<void> addStream(Stream<StreamMessage> stream) async {
    await for (final message in stream) {
      add(message);
    }
  }

  @override
  Future<void> close() => _stream._close();

  @override
  Future<void> get done => _stream._inner.outgoingMessages.done;
}

/// The call the daemon's services see: the gRPC handler plus the pressure of
/// its response stream.
class YaguraCall extends ServerHandler {
  YaguraCall({
    required PressureStream stream,
    required super.serviceLookup,
    super.clientCertificate,
    super.remoteAddress,
    super.onDataReceived,
  }) : pressure = stream,
       super(
         stream: stream,
         interceptors: const [],
         serverInterceptors: const [],
         codecRegistry: null,
       );

  final PressureStream pressure;

  /// Every non-OK status carries an `ErrorDetail`, also the ones the handler
  /// makes itself (a request that does not decode, a missing request message)
  /// before any service method runs. Statuses that already carry one pass.
  @override
  void sendTrailers({
    int? status = 0,
    String? message,
    Map<String, String>? errorTrailers,
  }) {
    if (status == null ||
        status == StatusCode.ok ||
        (errorTrailers?.containsKey(errorDetailsHeader) ?? false)) {
      super.sendTrailers(
        status: status,
        message: message,
        errorTrailers: errorTrailers,
      );
      return;
    }
    // The decoder's own message names internals of the generated code.
    final error = toGrpcError(
      GrpcError.custom(
        status,
        message != null && message.startsWith(_decodeFailure)
            ? 'the request message could not be decoded'
            : message,
      ),
      StackTrace.empty,
      method: 'transport',
      log: (_) {},
    );
    super.sendTrailers(
      status: error.code,
      message: error.message,
      errorTrailers: {...?errorTrailers, ...?error.trailers},
    );
  }
}

/// How package:grpc starts the message of a request that failed to decode.
const _decodeFailure = 'Error deserializing request';

/// A [Server] whose calls are [YaguraCall]s.
class YaguraGrpcServer extends Server {
  YaguraGrpcServer.create({
    required super.services,
    super.keepAliveOptions,
    this.requestLimit = maxRequestBytes,
    this.responseLimit = maxResponseBytes,
  }) : super.create();

  final int requestLimit;
  final int responseLimit;

  @override
  ServerHandler serveStream_({
    required ServerTransportStream stream,
    X509Certificate? clientCertificate,
    InternetAddress? remoteAddress,
    Sink<void>? onDataReceived,
  }) {
    return YaguraCall(
      stream: PressureStream(
        stream,
        requestLimit: requestLimit,
        responseLimit: responseLimit,
      ),
      serviceLookup: lookupService,
      clientCertificate: clientCertificate,
      remoteAddress: remoteAddress,
      onDataReceived: onDataReceived,
    )..handle();
  }
}
