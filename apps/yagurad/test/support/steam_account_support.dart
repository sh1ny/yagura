import 'dart:async';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/host/secret_store.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/steam/steam.dart';

import 'api_support.dart';
import 'daemon_support.dart';
import 'secret_support.dart';
import 'steam_support.dart';

/// A password no other text in the tests contains.
const testPassword = 'Zq7!hunter2-Zq7';

/// The login script rules the account tests share. SteamCMD is given
/// `+login <user> <password> [<code>]`, so the number of arguments after
/// `+login` says which run it is: 1 is a login with the cached credentials, 2
/// a login with a password and 3 one with a code as well.
Map<String, Object?> loginRule(
  int argc,
  String scenario, {
  String? user,
  String? creates,
  String? unless,
}) => {
  'argc': argc,
  'scenario': scenario,
  'user': ?user,
  'creates': ?creates,
  'unless': ?unless,
};

/// A daemon behind a loopback API with a Steam service that talks to the fake
/// SteamCMD, and helpers to drive account operations through the API.
class AccountRig {
  AccountRig._(this.env, this.steam, this.daemon, this.api);

  final TestEnv env;
  final SteamHarness steam;
  final Daemon daemon;
  final ApiHarness api;

  /// [login] is the Valheim fixture's `steam.login`.
  static Future<AccountRig> start({
    String login = 'account',
    TestEnv? env,
    bool realOutput = true,
    Map<String, String> fakeEnvironment = const {},
    Duration? codeWait,
    Duration? mobileWait,
    Duration? loginSilence,
    Duration? loginCap,
    SteamCmdBootstrap? bootstrap,
    bool ready = true,
    SecretProtector? secretProtector,
    int maxRetainedOperationEvents = 2000,
    // Edits the installed plugin before the daemon loads it.
    void Function(TestEnv env)? editPlugin,
    // Real snapshots in `<data>/snapshots` instead of the fake.
    bool realSnapshots = false,
  }) async {
    final testEnv = env ?? TestEnv();
    if (login == 'anonymous') {
      testEnv.installValheim();
    } else {
      testEnv.installValheim(from: 'login: anonymous', to: 'login: $login');
    }
    editPlugin?.call(testEnv);
    final steam = SteamHarness(
      testEnv,
      realOutput: realOutput,
      fakeEnvironment: fakeEnvironment,
      codeWait: codeWait,
      mobileWait: mobileWait,
      loginSilence: loginSilence,
      loginCap: loginCap,
      bootstrap: bootstrap ?? DirectoryBootstrap(),
      ready: ready,
    );
    final daemon = await testEnv.start(
      steamService: steam.service,
      secretProtector: secretProtector ?? FakeSecretProtector(devSid),
      maxRetainedOperationEvents: maxRetainedOperationEvents,
      realSnapshots: realSnapshots,
    );
    final api = await ApiHarness.start(testEnv, daemon: daemon);
    return AccountRig._(testEnv, steam, daemon, api);
  }

  pb.SteamClient get client => api.steam;

  Future<pb.Operation> add(
    String username, {
    String password = testPassword,
    bool remember = false,
  }) => client.addAccount(
    pb.AddAccountRequest(
      username: username,
      password: password,
      rememberPassword: remember,
    ),
  );

  Future<pb.Operation> reauth(
    String accountId, {
    String password = testPassword,
    bool remember = false,
  }) => client.reauthAccount(
    pb.ReauthAccountRequest(
      accountId: accountId,
      password: password,
      rememberPassword: remember,
    ),
  );

  Future<List<pb.SteamAccount>> accounts() async =>
      (await client.listAccounts(pb.ListAccountsRequest())).accounts;

  /// The listed account of [username].
  Future<pb.SteamAccount> accountNamed(String username) async =>
      (await accounts()).singleWhere((a) => a.username == username);

  Future<pb.Operation> operation(String id) =>
      api.operations.getOperation(pb.GetOperationRequest(operationId: id));

  /// Waits for [id] to wait for input and returns it with its prompt.
  Future<pb.Operation> waitForPrompt(String id) => poll(() async {
    final op = await operation(id);
    return op.status == pb.OperationStatus.OPERATION_STATUS_WAITING_FOR_INPUT
        ? op
        : null;
  }, 'operation $id to wait for input');

  /// Waits for [id] to end and returns it.
  Future<pb.Operation> finish(String id) => poll(() async {
    final op = await operation(id);
    return switch (op.status) {
      pb.OperationStatus.OPERATION_STATUS_SUCCEEDED ||
      pb.OperationStatus.OPERATION_STATUS_FAILED ||
      pb.OperationStatus.OPERATION_STATUS_CANCELLED ||
      pb.OperationStatus.OPERATION_STATUS_INTERRUPTED => op,
      _ => null,
    };
  }, 'operation $id to end');

  Future<pb.Operation> respond(pb.Operation op, String value) =>
      api.operations.respondToPrompt(
        pb.RespondToPromptRequest(
          operationId: op.id,
          promptId: op.pendingPrompt.id,
          value: value,
        ),
      );

  /// Adds [username] when SteamCMD answers a password login with success.
  Future<pb.SteamAccount> addReady(
    String username, {
    bool remember = false,
    String password = testPassword,
  }) async {
    steam.script.rules([loginRule(2, 'code_accepted')]);
    final op = await finish(
      (await add(username, remember: remember, password: password)).id,
    );
    expect(
      op.status,
      pb.OperationStatus.OPERATION_STATUS_SUCCEEDED,
      reason: op.resultMessage,
    );
    return accountNamed(username);
  }

  /// A Valheim instance linked to [accountId].
  Future<Instance> linkedInstance(
    String accountId, {
    String name = 'Friends',
  }) => daemon.instances.create(
    CreateInstanceRequest(
      pluginId: 'valheim',
      name: name,
      settings: valheimSettings(name: name),
      steamAccountId: accountId,
    ),
  );

  /// The installation directory of the account.
  String installationOf(String accountId) => p.join(steam.root, accountId);

  /// The directories of `<data>/steamcmd` other than the anonymous one.
  List<String> accountInstallations() {
    final root = Directory(steam.root);
    if (!root.existsSync()) return const [];
    return [
      for (final e in root.listSync())
        if (e is Directory && p.basename(e.path) != 'anonymous')
          p.basename(e.path),
    ];
  }

  /// The login runs the fake recorded, as the arguments after `+login`.
  List<List<String>> loginArguments() => [
    for (final run in steam.runs())
      if (run['login'] != null) _afterLogin((run['args']! as List).cast()),
  ];

  static List<String> _afterLogin(List<String> args) {
    final start = args.indexOf('+login') + 1;
    final out = <String>[];
    for (var i = start; i < args.length && !args[i].startsWith('+'); i++) {
      out.add(args[i]);
    }
    return out;
  }
}

/// Polls [fetch] until it returns a value.
Future<T> poll<T>(
  Future<T?> Function() fetch,
  String what, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final value = await fetch();
    if (value != null) return value;
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

/// Every event of a `WatchOperation` stream, as they arrive.
class EventLog {
  EventLog(Stream<pb.OperationEvent> stream) {
    subscription = stream.listen(
      events.add,
      onError: (Object e) => error = e,
      onDone: () => done = true,
    );
    addTearDown(subscription.cancel);
  }

  /// Watches [operationId] from [after].
  factory EventLog.of(ApiHarness api, String operationId, {int after = 0}) =>
      EventLog(
        api.operations.watchOperation(
          pb.WatchOperationRequest(
            operationId: operationId,
            afterSequence: Int64(after),
          ),
        ),
      );

  final events = <pb.OperationEvent>[];
  late final StreamSubscription<pb.OperationEvent> subscription;
  Object? error;
  var done = false;

  Future<void> whenDone() async {
    await eventually(() => done || error != null, reason: 'the stream to end');
    if (error != null) fail('the stream failed: $error');
  }

  Iterable<pb.OperationEvent> get prompts => events.where((e) => e.hasPrompt());

  Iterable<pb.OperationEvent> get resolutions =>
      events.where((e) => e.hasPromptResolved());

  /// Every text the events carry, to look for something that must not be
  /// there.
  String get allText => [for (final e in events) e.writeToJson()].join('\n');
}

/// The text of every file below [directory], read as bytes: whether [needle]
/// is in any of them, and where.
List<String> filesContaining(Directory directory, String needle) {
  final found = <String>[];
  final bytes = needle.codeUnits;
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is! File) continue;
    final List<int> content;
    try {
      content = entity.readAsBytesSync();
    } on FileSystemException {
      continue;
    }
    if (_contains(content, bytes)) found.add(entity.path);
  }
  return found;
}

bool _contains(List<int> haystack, List<int> needle) {
  if (needle.isEmpty) return true;
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var j = 0;
    while (j < needle.length && haystack[i + j] == needle[j]) {
      j++;
    }
    if (j == needle.length) return true;
  }
  return false;
}
