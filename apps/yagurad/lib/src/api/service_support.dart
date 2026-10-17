import 'dart:async';

import 'package:grpc/grpc.dart';

import 'api_error.dart';

/// Where the API reports daemon-side incidents.
typedef LogSink = void Function(String line);

/// A [ServiceMethod] that answers like the one it wraps and turns every
/// failure into a status with an `ErrorDetail`.
///
/// It delegates the typed parts (request stream, decoding, encoding) to the
/// wrapped method so the generated request and response types stay intact.
class GuardedMethod extends ServiceMethod<dynamic, dynamic> {
  GuardedMethod(this._inner, this._path, this._log)
    : super(
        _inner.name,
        _inner.handler,
        _inner.streamingRequest,
        _inner.streamingResponse,
        // Closures, not tear-offs: the wrapped method's function types are
        // not subtypes of the dynamic ones.
        (data) => _inner.deserialize(data),
        (response) => _inner.serialize(response),
      );

  final ServiceMethod<dynamic, dynamic> _inner;
  final String _path;
  final LogSink _log;

  @override
  StreamController<dynamic> createRequestStream(
    StreamSubscription<dynamic> incoming,
  ) => _inner.createRequestStream(incoming);

  @override
  dynamic deserialize(List<int> data) => _inner.deserialize(data);

  @override
  List<int> serialize(dynamic response) => _inner.serialize(response);

  @override
  Stream<dynamic> handle(
    ServiceCall call,
    Stream<dynamic> requests,
    List<ServerInterceptor> interceptors,
  ) {
    final Stream<dynamic> responses;
    try {
      responses = _inner.handle(call, requests, interceptors);
    } on Object catch (e, st) {
      return Stream.error(_map(e, st), st);
    }
    return responses.cast<dynamic>().transform(
      StreamTransformer.fromHandlers(
        handleError: (error, stackTrace, sink) =>
            sink.addError(_map(error, stackTrace), stackTrace),
      ),
    );
  }

  GrpcError _map(Object error, StackTrace stackTrace) =>
      toGrpcError(error, stackTrace, method: _path, log: _log);
}

/// A method of a service this version does not build: it fails
/// `UNIMPLEMENTED` / `not_implemented` without reading its request.
class StubMethod extends GuardedMethod {
  StubMethod(super.inner, super.path, super.log);

  @override
  Stream<dynamic> handle(
    ServiceCall call,
    Stream<dynamic> requests,
    List<ServerInterceptor> interceptors,
  ) => Stream.error(
    grpcErrorFor(
      'not_implemented',
      '$_path is not implemented in this version',
    ),
  );
}

/// Mixed into a generated service base: every method it registers becomes a
/// [GuardedMethod].
///
/// The generated constructor registers its methods before the subclass has
/// any state, so [logSink] is read when a call arrives, not at registration.
mixin GuardedService on Service {
  LogSink get logSink;

  @override
  void $addMethod(ServiceMethod<dynamic, dynamic> method) => super.$addMethod(
    GuardedMethod(method, '${$name}/${method.name}', (line) => logSink(line)),
  );
}

/// Mixed into a generated service base to register every method as a
/// [StubMethod].
mixin StubService on Service {
  @override
  void $addMethod(ServiceMethod<dynamic, dynamic> method) =>
      super.$addMethod(StubMethod(method, '${$name}/${method.name}', (_) {}));
}
