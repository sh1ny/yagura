import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../api/bind_address.dart';
import '../errors.dart';
import 'account_purger.dart';
import 'bundle.dart';
import 'install_layout.dart';
import 'service_control.dart';
import 'winsw_config.dart';

/// Calls the running daemon over the admin channel.
typedef AdminCall = Future<Map<String, Object?>> Function(
  String command, [
  Map<String, Object?> args,
]);

/// Reasons of the admin channel that only mean the daemon is not up yet.
const _notYet = {
  'daemon_not_running',
  'admin_connection_closed',
  'admin_request_timeout',
  'admin_channel_busy',
};

/// `yagurad service install|configure|uninstall|status` (design D6).
///
/// Everything outside the logic is a seam: the service control manager and
/// WinSW ([ServiceControl]), the admin channel ([AdminCall]), the account
/// purge ([AccountPurger]) and the clock ([delay], [now]). The files go
/// wherever [layout] says, so tests install into a temporary directory.
class ServiceInstaller {
  ServiceInstaller({
    required this.layout,
    required this.control,
    this.bundle,
    this.loadBundle,
    required this.admin,
    required this.out,
    required this.isElevated,
    required this.servers,
    required this.purger,
    this.readyTimeout = const Duration(seconds: 60),
    this.pollInterval = const Duration(seconds: 1),
    this.delay = _wait,
    this.now = DateTime.now,
    this.lookup,
  });

  final InstallLayout layout;
  final ServiceControl control;

  /// The bundle to install; only `install` needs it.
  final Bundle? bundle;

  /// Finds the bundle when [bundle] is not given, and only when a command
  /// needs it: the elevation check comes before any look at the bundle.
  final Bundle Function()? loadBundle;
  final AdminCall admin;
  final StringSink out;
  final bool Function() isElevated;
  final ServerProbe servers;
  final AccountPurger purger;

  /// How long to wait for a state change of the service and for the daemon
  /// to answer (the 60 s of design D6).
  final Duration readyTimeout;
  final Duration pollInterval;
  final Future<void> Function(Duration) delay;
  final DateTime Function() now;

  /// Resolves a bind host name; defaults to the system resolver.
  final Future<List<InternetAddress>> Function(String host)? lookup;

  static Future<void> _wait(Duration d) => Future<void>.delayed(d);

  String get _name => layout.serviceName;

  late final Bundle _bundle =
      bundle ??
      loadBundle?.call() ??
      (throw YaguraException(
        'bundle_invalid',
        'this command needs the bundle it installs from',
      ));

  // ---- install ----------------------------------------------------------

  /// Registers the service and starts it, or upgrades an installed service
  /// to this bundle.
  Future<void> install({String? bind, String? dataDirectory}) async {
    _requireElevated();
    _bundle.validate();
    if (control.status(_name) != ServiceStatus.notInstalled) {
      return _upgrade(bind: bind, dataDirectory: dataDirectory);
    }
    final bindText = (bind ?? defaultServiceBindText).trim();
    await _checkBind(bindText);

    final config = ServiceConfig(
      layout: layout,
      version: _bundle.version,
      bind: bindText,
      dataDirectory: dataDirectory,
    );
    final xml = config.render(_bundle.readTemplate());
    final rootExisted = Directory(layout.root).existsSync();
    try {
      _copyVersion(_bundle.version);
      File(_bundle.winswExecutable).copySync(layout.winswExecutable);
      _write(layout.configFile, xml);
      await control.install(layout);
    } on Object {
      _removeInstallFiles(config, removeRoot: !rootExisted);
      rethrow;
    }
    await _start();
    final status = await _waitReady();
    out.writeln(
      'service $_name installed (version ${_bundle.version}) and running; '
      'listening on $bindText',
    );
    _printStatus(status);
    out.writeln(
      'Next: run `yagurad pair` from an elevated prompt to pair a device.',
    );
  }

  Future<void> _upgrade({String? bind, String? dataDirectory}) async {
    final installed = _readConfig(
      'service $_name is installed',
      reason: 'service_exists',
    );
    final order = compareVersions(_bundle.version, installed.version);
    if (order == 0) {
      throw YaguraException(
        'service_exists',
        'service $_name is already installed at version ${installed.version}; '
            'nothing was changed',
      );
    }
    if (order < 0) {
      throw YaguraException(
        'service_exists',
        'service $_name is installed at version ${installed.version}, which '
            'is newer than this bundle (${_bundle.version}); nothing was '
            'changed',
      );
    }
    if (bind != null || dataDirectory != null) {
      throw YaguraException(
        'service_exists',
        'service $_name is installed: an upgrade keeps its bind and data '
            'directory. Upgrade without --bind and --data-dir, and change '
            'the bind with `yagurad service configure --bind`',
      );
    }

    final oldXml = File(layout.configFile).readAsStringSync();
    final newXml = installed
        .withVersion(_bundle.version)
        .render(_bundle.readTemplate());
    _copyVersion(_bundle.version);
    // The old version directory stays: relays of running servers execute
    // its yagurad.exe, and replacing files they hold would end the servers.
    if (control.status(_name) != ServiceStatus.stopped) {
      await control.stop(layout);
      await _waitFor(ServiceStatus.stopped);
    }
    _write(layout.configFile, newXml);
    try {
      await control.start(layout);
    } on YaguraException {
      _write(layout.configFile, oldXml);
      try {
        await control.start(layout);
      } on YaguraException {
        // The original failure is the one to report.
      }
      rethrow;
    }
    await _waitFor(ServiceStatus.running);
    final status = await _waitReady();
    out.writeln(
      'service $_name upgraded from ${installed.version} to '
      '${_bundle.version} and running; running game servers were not '
      'stopped',
    );
    _printStatus(status);
  }

  // ---- configure --------------------------------------------------------

  /// Changes the API bind for the next service start.
  Future<void> configure({required String bind}) async {
    _requireElevated();
    if (control.status(_name) == ServiceStatus.notInstalled) {
      throw _notInstalled();
    }
    final text = bind.trim();
    final port = await _checkBind(text);
    final config = _readConfig('service $_name is installed');
    try {
      await admin('ports.check', {'port': port});
    } on YaguraException catch (e) {
      // With the daemon down there is nobody to ask; the daemon checks the
      // port again when it starts.
      if (e.reason != 'daemon_not_running') rethrow;
    }
    // The template is not here (the bundle's winsw directory is not part of
    // an installed version): change the arguments of the file in place.
    _write(
      layout.configFile,
      config
          .withBind(text)
          .replaceArguments(File(layout.configFile).readAsStringSync()),
    );
    out.writeln(
      'bind of service $_name set to $text; it applies at the next service '
      'start (Restart-Service $_name)',
    );
  }

  // ---- uninstall --------------------------------------------------------

  /// Stops and removes the service. Running game servers, the data
  /// directory and the accounts stay; [purgeAccounts] also deletes the
  /// accounts, but only when no server runs.
  Future<void> uninstall({bool purgeAccounts = false}) async {
    _requireElevated();
    final state = control.status(_name);
    if (state == ServiceStatus.notInstalled) throw _notInstalled();
    if (purgeAccounts) {
      final running = await servers.runningServers();
      if (running.isNotEmpty) {
        throw YaguraException(
          'servers_running',
          '--purge-accounts needs every game server stopped, and these run: '
              '${running.join(', ')}. Stop them, then run it again; nothing '
              'was changed',
          details: {'servers': running},
        );
      }
    }

    if (state != ServiceStatus.stopped) {
      await control.stop(layout);
      await _waitFor(ServiceStatus.stopped);
    }
    await control.uninstall(layout);
    final kept = _removeFiles();
    out.writeln('service $_name removed.');
    for (final version in kept) {
      out.writeln(
        'kept ${layout.versionDirectory(version)}: running game servers '
        'still execute from it; the daemon deletes it once they are gone',
      );
    }
    out.writeln(
      'The data directory, the service accounts and running game servers '
      'were left in place.',
    );

    if (purgeAccounts) {
      final outcomes = await purger.purge();
      final stayed = <PurgeOutcome>[];
      for (final outcome in outcomes) {
        if (outcome.removed) {
          out.writeln('removed account ${outcome.account} and its profile');
        } else {
          stayed.add(outcome);
          out.writeln('kept account ${outcome.account}: ${outcome.reason}');
        }
      }
      if (stayed.isNotEmpty) {
        throw YaguraException(
          'profile_in_use',
          'account ${stayed.map((o) => o.account).join(', ')} could not be '
              'removed yet (${stayed.first.reason}); once the processes using '
              'it have exited, run `yagurad service uninstall '
              '--purge-accounts` again',
        );
      }
    }
  }

  /// Deletes the configuration, the wrapper and every version directory it
  /// can; returns the versions it had to keep.
  List<String> _removeFiles() {
    for (final path in [layout.configFile, layout.winswExecutable]) {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    }
    final kept = <String>[];
    final root = Directory(layout.root);
    if (!root.existsSync()) return kept;
    // What the wrapper wrote: its logs folder, and files named after the
    // service. A file still open keeps its folder (best effort).
    final prefix = '${layout.serviceName}.';
    for (final entity in root.listSync(followLinks: false)) {
      final name = p.basename(entity.path);
      final isLogs =
          entity is Directory && name == p.basename(layout.logDirectory);
      final isWrapperFile = entity is File && name.startsWith(prefix);
      if (!isLogs && !isWrapperFile) continue;
      try {
        entity.deleteSync(recursive: true);
      } on FileSystemException {
        // Reported by the root that stays.
      }
    }
    for (final entity in root.listSync(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is! Directory || !isVersionName(name)) continue;
      try {
        entity.deleteSync(recursive: true);
      } on FileSystemException {
        kept.add(name);
      }
    }
    if (root.listSync().isEmpty) root.deleteSync();
    return kept;
  }

  // ---- status -----------------------------------------------------------

  /// Prints the state of the service and, when it runs, what the daemon
  /// reports.
  Future<void> status() async {
    _requireElevated();
    final state = control.status(_name);
    if (state == ServiceStatus.notInstalled) throw _notInstalled();
    out.writeln('service: $_name');
    out.writeln('state: ${_stateName(state)}');
    final xml = File(layout.configFile);
    final config = xml.existsSync()
        ? ServiceConfig.parse(xml.readAsStringSync(), layout)
        : null;
    if (config == null) {
      out.writeln('config: ${layout.configFile} is missing or not ours');
    } else {
      out.writeln('version: ${config.version}');
      out.writeln('bind: ${config.bind}');
      if (config.dataDirectory case final data?) {
        out.writeln('data_dir: $data');
      }
    }
    if (state != ServiceStatus.running) return;
    try {
      _printStatus(await admin('status'));
    } on YaguraException catch (e) {
      out.writeln('daemon: ${e.reason}: ${e.message}');
    }
  }

  // ---- helpers ----------------------------------------------------------

  void _requireElevated() {
    if (isElevated()) return;
    throw YaguraException(
      'elevation_required',
      'run this command from an elevated prompt (Run as administrator)',
    );
  }

  YaguraException _notInstalled() => YaguraException(
    'service_not_installed',
    'service $_name is not installed; run `yagurad service install`',
  );

  /// Checks the bind reads and names a port; returns the port.
  Future<int> _checkBind(String bind) async {
    final parsed = await parseServiceBind(
      bind,
      lookup: lookup ?? InternetAddress.lookup,
    );
    if (parsed.port < 1) {
      throw YaguraException(
        'bind_invalid',
        'the bind "$bind" needs a port from 1 to 65535',
      );
    }
    return parsed.port;
  }

  ServiceConfig _readConfig(
    String what, {
    String reason = 'service_config_invalid',
  }) {
    final file = File(layout.configFile);
    final config = file.existsSync()
        ? ServiceConfig.parse(file.readAsStringSync(), layout)
        : null;
    if (config == null) {
      throw YaguraException(
        reason,
        '$what, but ${layout.configFile} is missing or was not written by '
        '`yagurad service install`; nothing was changed. Remove the '
        'service with `yagurad service uninstall` and install it again',
      );
    }
    return config;
  }

  void _copyVersion(String version) {
    final directory = layout.versionDirectory(version);
    try {
      if (Directory(directory).existsSync()) {
        Directory(directory).deleteSync(recursive: true);
      }
      _bundle.copyTo(directory);
    } on FileSystemException catch (e) {
      throw YaguraException(
        'install_failed',
        'cannot copy the bundle to $directory: ${e.message} ${e.path ?? ''}'
            .trimRight(),
      );
    }
  }

  /// Writes [text] through a temporary file, so a reader (WinSW at service
  /// start) never sees half of it.
  void _write(String path, String text) {
    Directory(p.dirname(path)).createSync(recursive: true);
    final temporary = File('$path.tmp')..writeAsStringSync(text);
    temporary.renameSync(path);
  }

  void _removeInstallFiles(ServiceConfig config, {required bool removeRoot}) {
    void tryDelete(FileSystemEntity entity) {
      try {
        if (entity.existsSync()) entity.deleteSync(recursive: true);
      } on FileSystemException {
        // Best effort: what remains is overwritten by the next install.
      }
    }

    tryDelete(File(layout.configFile));
    tryDelete(File('${layout.configFile}.tmp'));
    tryDelete(File(layout.winswExecutable));
    tryDelete(Directory(layout.versionDirectory(config.version)));
    if (removeRoot) {
      final root = Directory(layout.root);
      try {
        if (root.existsSync() && root.listSync().isEmpty) root.deleteSync();
      } on FileSystemException {
        // As above.
      }
    }
  }

  Future<void> _start() async {
    await control.start(layout);
    await _waitFor(ServiceStatus.running);
  }

  Future<void> _waitFor(ServiceStatus wanted) async {
    final deadline = now().add(readyTimeout);
    while (control.status(_name) != wanted) {
      if (!now().isBefore(deadline)) {
        throw YaguraException(
          'service_timeout',
          'service $_name did not become ${_stateName(wanted)} within '
              '${readyTimeout.inSeconds} s; see ${layout.logDirectory}',
        );
      }
      await delay(pollInterval);
    }
  }

  /// Polls `status` over the admin pipe until the daemon answers.
  Future<Map<String, Object?>> _waitReady() async {
    final deadline = now().add(readyTimeout);
    String last = 'no answer';
    while (now().isBefore(deadline)) {
      try {
        return await admin('status');
      } on YaguraException catch (e) {
        if (!_notYet.contains(e.reason)) rethrow;
        last = '${e.reason}: ${e.message}';
      }
      await delay(pollInterval);
    }
    throw YaguraException(
      'service_not_ready',
      'service $_name is running, but the daemon did not answer on the admin '
          'channel within ${readyTimeout.inSeconds} s (last: $last). Read the '
          'log in ${layout.logDirectory} and the daemon log in its data '
          'directory',
    );
  }

  void _printStatus(Map<String, Object?> status) {
    for (final MapEntry(:key, :value) in status.entries) {
      out.writeln('  $key: $value');
    }
  }

  static String _stateName(ServiceStatus state) => switch (state) {
    ServiceStatus.notInstalled => 'not installed',
    ServiceStatus.stopped => 'stopped',
    ServiceStatus.startPending => 'starting',
    ServiceStatus.stopPending => 'stopping',
    ServiceStatus.running => 'running',
  };
}
