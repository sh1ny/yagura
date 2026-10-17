import 'package:yagura_proto/yagura_proto.dart' as pb;

import 'service_support.dart';

// Services this version does not build are registered anyway: package:grpc
// answers a call to an unknown service before any interceptor runs and would
// send no ErrorDetail (design D24). Every method of a stub fails
// UNIMPLEMENTED / not_implemented; the generated methods are never called, so
// noSuchMethod stands in for them.

class PairingStub extends pb.PairingServiceBase with StubService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SteamStub extends pb.SteamServiceBase with StubService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ModsStub extends pb.ModsServiceBase with StubService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RconStub extends pb.RconServiceBase with StubService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FirewallStub extends pb.FirewallServiceBase with StubService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
