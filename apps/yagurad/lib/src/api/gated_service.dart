import 'dart:async';

import 'package:grpc/grpc.dart';

import '../security/auth_gate.dart';
import 'api_error.dart';

/// Wraps every method of [inner] so the [AuthGate] decides before it runs
/// (design D2). The reflection services go through the same wrapper, so no
/// service is served around the gate.
class GatedService extends Service {
  GatedService(this.inner, this.gate);

  final Service inner;
  final AuthGate gate;
  final _methods = <String, GatedMethod>{};

  @override
  String get $name => inner.$name;

  @override
  void $onMetadata(ServiceCall context) => inner.$onMetadata(context);

  // Looked up, not copied: a method the service adds later is behind the
  // gate too.
  @override
  ServiceMethod<dynamic, dynamic>? $lookupMethod(String name) {
    final method = inner.$lookupMethod(name);
    if (method == null) return null;
    return _methods.putIfAbsent(
      name,
      () => GatedMethod(method, '${inner.$name}/$name', gate),
    );
  }
}

/// One method behind the gate. A refused call never reaches the handler;
/// an allowed one is registered under its device so a revocation can end it,
/// and a state-changing one is audited when it ends.
class GatedMethod extends ServiceMethod<dynamic, dynamic> {
  GatedMethod(this._inner, this._path, this._gate)
    : super(
        _inner.name,
        _inner.handler,
        _inner.streamingRequest,
        _inner.streamingResponse,
        (data) => _inner.deserialize(data),
        (response) => _inner.serialize(response),
      );

  final ServiceMethod<dynamic, dynamic> _inner;

  /// `package.Service/Method`.
  final String _path;
  final AuthGate _gate;

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
    // Dev mode: nothing to decide, record or end; the call runs as it is.
    if (!_gate.authenticates) {
      return _inner.handle(call, requests, interceptors);
    }
    final CallPermit permit;
    try {
      permit = _gate.authorize(call, _path);
    } on GrpcError catch (e) {
      // The request is still drained: an HTTP/2 stream left unread stays
      // registered and trips http2's assertion when the connection closes.
      unawaited(requests.drain<void>().catchError((Object _) {}));
      return Stream.error(e);
    }
    // The request stream keeps its element type (the handler is typed by
    // it), so it is rebuilt by the method that made it; the first message
    // names the target of the audit entry.
    final incoming = requests.listen(null)..pause();
    final tapped = _inner.createRequestStream(incoming);
    var first = true;
    incoming
      ..onData((message) {
        if (first) {
          first = false;
          permit.target = auditTarget(message);
        }
        tapped.add(message);
      })
      ..onError(tapped.addError)
      ..onDone(() => unawaited(tapped.close()));
    final Stream<dynamic> responses;
    try {
      responses = _inner.handle(call, tapped.stream, const []);
    } on Object catch (e, st) {
      permit.release();
      return Stream.error(e, st);
    }

    late final StreamController<dynamic> out;
    StreamSubscription<dynamic>? subscription;
    var finished = false;
    void finish(String result) {
      if (finished) return;
      finished = true;
      permit.release();
      _gate.finished(permit, _path, result);
    }

    permit.revoke = () {
      if (finished) return;
      finish('device_revoked');
      unawaited(subscription?.cancel());
      out
        ..addError(grpcErrorFor('device_revoked', 'this device was revoked'))
        ..close();
    };
    out = StreamController<dynamic>(
      onListen: () {
        subscription = responses.listen(
          out.add,
          onError: (Object error, StackTrace stackTrace) {
            finish(reasonOfError(error));
            out.addError(error, stackTrace);
          },
          onDone: () {
            finish('ok');
            out.close();
          },
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        finish('cancelled');
        return subscription?.cancel();
      },
    );
    return out.stream;
  }
}
