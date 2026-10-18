import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/service/account_purger.dart';
import 'package:yagurad/src/service/bundle.dart';
import 'package:yagurad/src/service/install_layout.dart';
import 'package:yagurad/src/service/service_control.dart';
import 'package:yagurad/src/service/service_installer.dart';

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

  @override
  Future<List<String>> runningServers() async => running;
}

class FakePurger implements AccountPurger {
  List<PurgeOutcome> outcomes = const [
    PurgeOutcome('yagura-srv', removed: true),
    PurgeOutcome('yagura-steam', removed: true),
  ];
  var calls = 0;

  @override
  Future<List<PurgeOutcome>> purge() async {
    calls++;
    return outcomes;
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

  /// Answers other admin commands.
  FutureOr<Map<String, Object?>> Function(
    String command,
    Map<String, Object?> args,
  )
  other = (command, args) =>
      throw YaguraException('daemon_not_running', 'nothing serves the pipe');

  late ServiceInstaller installer;

  ServiceInstaller _make() => ServiceInstaller(
    layout: layout,
    control: control,
    bundle: bundle,
    admin: (command, [args = const {}]) async {
      adminCalls.add(command);
      if (command == 'status') return status(polls++);
      return other(command, args);
    },
    out: out,
    isElevated: () => elevated,
    servers: servers,
    purger: purger,
    delay: (d) async => clock = clock.add(d),
    now: () => clock,
  );

  /// Installs [version] next to what is there; a new bundle for the next
  /// command.
  void useBundle(String version) {
    bundle = makeBundle(version, parent: root);
    installer = _make();
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
