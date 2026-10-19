import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/firewall/api_port_rule.dart';
import 'package:yagurad/src/instances/instance_roots.dart'
    show administratorsSid;
import 'package:yagurad/src/platform/acl_inspector.dart';
import 'package:yagurad/src/platform/acl_writer.dart';
import 'package:yagurad/src/service/account_purger.dart';
import 'package:yagurad/src/service/bundle.dart';
import 'package:yagurad/src/service/install_layout.dart';
import 'package:yagurad/src/service/service_control.dart';
import 'package:yagurad/src/service/service_installer.dart';

import 'admin_support.dart';

/// The directory of the WinSW binary and template in the repository, seen
/// from `apps/yagurad`.
const winswSourceDirectory = '../../tool/winsw';

/// A bundle laid out like the release one, in a temporary directory: the
/// executable and library are placeholders, WinSW and the template are the
/// repository's.
Bundle makeBundle(String version, {Directory? parent, bool withWinsw = true}) {
  final root = (parent ?? Directory.systemTemp.createTempSync('yagurad_b_'))
      .createTempSync('bundle_');
  File(p.join(root.path, 'bin', 'yagurad.exe'))
    ..createSync(recursive: true)
    ..writeAsStringSync('yagurad $version');
  File(p.join(root.path, 'lib', 'sqlite3.dll'))
    ..createSync(recursive: true)
    ..writeAsStringSync('native');
  if (withWinsw) {
    for (final name in ['WinSW.NET461.exe', 'yagurad.xml.template']) {
      File(p.join(winswSourceDirectory, name)).copySync(
        (File(
          p.join(root.path, 'winsw', name),
        )..createSync(recursive: true)).path,
      );
    }
  }
  return Bundle(root: root.path, version: version);
}

/// A [ServiceControl] that keeps the services in memory and checks what
/// WinSW would check: the wrapper and its configuration exist.
class FakeServiceControl implements ServiceControl {
  final services = <String, ServiceStatus>{};
  final calls = <String>[];

  /// Fails the next call of this name with `service_command_failed`.
  final failing = <String>{};

  /// The configuration each `install` saw.
  final installedConfigs = <String>[];

  @override
  ServiceStatus status(String serviceName) =>
      services[serviceName] ?? ServiceStatus.notInstalled;

  @override
  Future<List<String>> yaguraServices() async => services.keys.toList();

  void _call(String name, InstallLayout layout) {
    calls.add(name);
    if (failing.remove(name)) {
      throw YaguraException('service_command_failed', 'fake $name failed');
    }
    expect(
      File(layout.winswExecutable).existsSync(),
      isTrue,
      reason: 'WinSW $name needs the wrapper in place',
    );
  }

  @override
  Future<void> install(InstallLayout layout) async {
    _call('install', layout);
    installedConfigs.add(File(layout.configFile).readAsStringSync());
    services[layout.serviceName] = ServiceStatus.stopped;
  }

  @override
  Future<void> uninstall(InstallLayout layout) async {
    _call('uninstall', layout);
    expect(status(layout.serviceName), ServiceStatus.stopped);
    services.remove(layout.serviceName);
  }

  @override
  Future<void> start(InstallLayout layout) async {
    _call('start', layout);
    services[layout.serviceName] = ServiceStatus.running;
  }

  @override
  Future<void> stop(InstallLayout layout) async {
    _call('stop', layout);
    services[layout.serviceName] = ServiceStatus.stopped;
  }
}

class FakeServers implements ServerProbe {
  List<String> running = [];

  /// Answers given one per call before [running] applies; for a server that
  /// starts between two looks.
  final answers = <List<String>>[];
  var calls = 0;

  /// The calls (counted from 1) that throw instead of answering.
  final failAt = <int>{};

  @override
  Future<List<String>> runningServers() async {
    calls++;
    if (failAt.contains(calls)) {
      throw YaguraException('admin_connection_closed', 'the pipe is closing');
    }
    return answers.isEmpty ? running : answers.removeAt(0);
  }
}

class FakePurger implements AccountPurger {
  List<PurgeOutcome> outcomes = const [
    PurgeOutcome('yagura-srv', removed: true),
    PurgeOutcome('yagura-steam', removed: true),
  ];
  var calls = 0;

  /// The data directory each purge was told to use.
  final dataDirectories = <String?>[];

  @override
  Future<List<PurgeOutcome>> purge({String? dataDirectory}) async {
    calls++;
    dataDirectories.add(dataDirectory);
    return outcomes;
  }
}

/// An ACL inspector over the rig's files: it answers what the fake writer
/// would (see [FakeAclWriter.securityOf]).
class FakeAclInspector implements AclInspector {
  FakeAclInspector(this.writer);

  final FakeAclWriter writer;
  final inspected = <String>[];

  /// Answers by path; checked first.
  Map<String, EntrySecurity> get overrides => writer.overrides;

  @override
  EntrySecurity inspect(String path) {
    inspected.add(path);
    return writer.securityOf(path);
  }
}

/// A [ServiceInstaller] over a temporary install root and fakes, with a
/// clock that jumps when the installer waits.
class InstallerRig {
  InstallerRig({
    String version = '0.1.0',
    String serviceName = defaultServiceName,
    this.elevated = true,
    Bundle? bundle,
  }) : root = Directory.systemTemp.createTempSync('yagurad_install_') {
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    layout = InstallLayout(
      root: p.join(root.path, 'ProgramFiles', 'Yagura'),
      serviceName: serviceName,
    );
    // The parent of the install root: `Program Files`.
    Directory(p.dirname(layout.root)).createSync(recursive: true);
    this.bundle = bundle ?? makeBundle(version, parent: root);
    installer = _make();
  }

  final Directory root;
  bool elevated;
  late final InstallLayout layout;
  late Bundle bundle;
  final control = FakeServiceControl();
  final servers = FakeServers();
  final purger = FakePurger();
  final acl = FakeAclWriter();
  late final inspector = FakeAclInspector(acl);
  AclWriter? _aclWriter;
  final out = StringBuffer();
  final adminCalls = <String>[];
  var clock = DateTime.utc(2026, 1, 1);

  /// What `status` answers; throws when it is an exception. Called once per
  /// poll with the number of the poll.
  FutureOr<Map<String, Object?>> Function(int poll) status = (_) => {
    'mode': 'service',
    'version': '0.1.0',
    'api_port': 7443,
  };
  var polls = 0;

  /// Whether another service's daemon holds the admin channel: `status`
  /// answers even while this service is not running.
  bool foreignDaemon = false;

  /// Answers other admin commands.
  FutureOr<Map<String, Object?>> Function(
    String command,
    Map<String, Object?> args,
  )
  other = (command, args) =>
      throw YaguraException('daemon_not_running', 'nothing serves the pipe');

  late ServiceInstaller installer;

  /// Runs each time the installer waits; a file locked a moment ago can be
  /// released here.
  void Function()? onDelay;

  ApiPortRule? _apiRule;

  /// Gives the installer the API port rule it creates and removes.
  set apiRule(ApiPortRule rule) {
    _apiRule = rule;
    installer = _make();
  }

  /// Replaces the ACL writer of the installer.
  set aclWriter(AclWriter writer) {
    _aclWriter = writer;
    installer = _make();
  }

  ServiceInstaller _make() => ServiceInstaller(
    layout: layout,
    control: control,
    bundle: bundle,
    admin: (command, [args = const {}]) async {
      adminCalls.add(command);
      if (command == 'status') {
        // The channel has one name: nothing answers unless this service runs
        // or another one holds it.
        if (!foreignDaemon &&
            control.status(layout.serviceName) != ServiceStatus.running) {
          throw YaguraException(
            'daemon_not_running',
            'nothing serves the pipe',
          );
        }
        return status(polls++);
      }
      return other(command, args);
    },
    out: out,
    isElevated: () => elevated,
    servers: servers,
    purger: purger,
    apiRule: _apiRule,
    aclWriter: _aclWriter ?? acl,
    inspector: inspector,
    delay: (d) async {
      clock = clock.add(d);
      onDelay?.call();
    },
    now: () => clock,
  );

  /// Installs [version] next to what is there; a new bundle for the next
  /// command.
  void useBundle(String version) {
    bundle = makeBundle(version, parent: root);
    installer = _make();
  }

  /// Gives the install root the protection an earlier install of this tool
  /// leaves on it, as the elevated tool would have.
  void preprotect() {
    Directory(layout.root).createSync(recursive: true);
    acl.open(layout.root)
      ..writeDacl(installRootDaclSddl, ownerSid: administratorsSid)
      ..close();
  }

  String get serviceName => layout.serviceName;
  String get output => '$out';
  bool get rootExists => Directory(layout.root).existsSync();
  String configText() => File(layout.configFile).readAsStringSync();
}

/// Runs [body] and returns the [YaguraException] it throws.
Future<YaguraException> failureOf(Future<void> Function() body) async {
  try {
    await body();
  } on YaguraException catch (e) {
    return e;
  }
  fail('expected a YaguraException');
}
