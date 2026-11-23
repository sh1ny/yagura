import 'package:grpc/grpc.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;

import '../host/daemon.dart';
import 'convert.dart';
import 'service_support.dart';

/// The `Steam` service (design D1): the daemon's Steam accounts. Adding one and
/// logging one in again are operations; Steam Guard arrives as a prompt on
/// them.
class SteamApi extends pb.SteamServiceBase with GuardedService {
  SteamApi(this.daemon, this.logSink);

  final Daemon daemon;

  @override
  final LogSink logSink;

  @override
  Future<pb.ListAccountsResponse> listAccounts(
    ServiceCall call,
    pb.ListAccountsRequest request,
  ) async => _accounts();

  @override
  Future<pb.Operation> addAccount(
    ServiceCall call,
    pb.AddAccountRequest request,
  ) async => operationToPb(
    daemon.steamAccounts.add(
      username: request.username,
      password: request.password,
      rememberPassword: request.rememberPassword,
    ),
  );

  @override
  Future<pb.Operation> reauthAccount(
    ServiceCall call,
    pb.ReauthAccountRequest request,
  ) async => operationToPb(
    daemon.steamAccounts.reauth(
      accountId: request.accountId,
      password: request.password,
      rememberPassword: request.rememberPassword,
    ),
  );

  @override
  Future<pb.ListAccountsResponse> removeAccount(
    ServiceCall call,
    pb.RemoveAccountRequest request,
  ) async {
    await daemon.steamAccounts.remove(request.accountId);
    return _accounts();
  }

  pb.ListAccountsResponse _accounts() => pb.ListAccountsResponse(
    accounts: [
      for (final a in daemon.steamAccounts.list()) steamAccountToPb(a),
    ],
  );
}
