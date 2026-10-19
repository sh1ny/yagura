import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../api/bind_address.dart';
import '../errors.dart';
import '../firewall/api_port_rule.dart';
import '../firewall/firewall_backend.dart' show FirewallUnavailable;
import '../firewall/rule_names.dart' show apiRuleName;
import '../instances/instance_roots.dart' show administratorsSid;
import '../platform/acl_inspector.dart';
import '../platform/acl_writer.dart';
import 'account_purger.dart';
import 'bundle.dart';
import 'install_layout.dart';
import 'install_root_security.dart';
import 'service_control.dart';
import 'winsw_config.dart';

/// Calls the running daemon over the admin channel.
typedef AdminCall = Future<Map<String, Object?>> Function(
  String command, [
  Map<String, Object?> args,
]);

/// The DACL of the install root and of each version directory (ADR 0015): the
/// files run as LocalSystem, so only SYSTEM and Administrators may change
/// them. Users (and so the service accounts) read and execute. Protected, so
/// nothing is inherited from a parent a user may have made; inherited by what
/// is created below.
const installRootDaclSddl =
    'D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;BU)';

/// Reasons of the admin channel that only mean the daemon is not up yet.
const _notYet = {
  'daemon_not_running',
  'admin_connection_closed',
  'admin_request_timeout',
  'admin_channel_busy',
  'daemon_starting',
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
    required this.aclWriter,
    required this.inspector,
    this.apiRule,
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

  /// Protects the install root (ADR 0015).
  final AclWriter aclWriter;

  /// Reads the owner and DACL of the folders above and at the install root.
  final AclInspector inspector;

  /// Creates and removes the API port rule (design D11); null manages none.
  final ApiPortRule? apiRule;

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
    _requirePlainPath('the install directory', layout.root);
    _checkAncestors();
    if (control.status(_name) != ServiceStatus.notInstalled) {
      return _upgrade(bind: bind, dataDirectory: dataDirectory);
    }
    // One Yagura service per host: it manages the firewall group and holds
    // the admin channel. `--service-name` exists for the test rig.
    final others = [
      for (final name in await control.yaguraServices())
        if (name != _name) name,
    ];
    if (others.isNotEmpty) {
      throw YaguraException(
        'another_service_installed',
        'the Yagura service ${others.first} is already installed, and a host '
            'runs one; nothing was changed. Upgrade it by running install '
            'with its name, or uninstall it first',
      );
    }
    final bindText = (bind ?? defaultServiceBindText).trim();
    final port = await _checkBind(bindText);
    // The service resolves a relative path against its own directory, and
    // the commands that read the data directory against theirs.
    final data = dataDirectory == null
        ? null
        : p.normalize(p.absolute(dataDirectory));
    if (data != null) _requirePlainPath('the data directory', data);

    final config = ServiceConfig(
      layout: layout,
      version: _bundle.version,
      bind: bindText,
      dataDirectory: data,
    );
    final xml = config.render(_bundle.readTemplate());
    final rootExisted = Directory(layout.root).existsSync();
    final versionExisted = Directory(layout.versionDirectory(_bundle.version))
        .existsSync();
    // Before the try: a refused root is not ours, and the clean-up below must
    // not touch anything in it.
    _protectRoot();
    try {
      _copyVersion(_bundle.version);
      _copyWrapper();
      _write(layout.configFile, xml);
      await control.install(layout);
    } on Object catch (e) {
      _removeInstallFiles(
        config,
        removeRoot: !rootExisted,
        removeVersion: !versionExisted,
      );
      if (e is FileSystemException) {
        throw YaguraException(
          'install_failed',
          'cannot write ${e.path ?? layout.root}: ${e.message}',
        );
      }
      rethrow;
    }
    await _ensureApiRule(port);
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
    _protectRoot();
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
  ///
  /// The files are removed best effort: one that cannot be deleted is
  /// reported and left, and the purge runs anyway. When an earlier uninstall
  /// left its files behind (the service is gone from the service manager,
  /// its configuration is not), `--purge-accounts` finishes the job.
  Future<void> uninstall({bool purgeAccounts = false}) async {
    _requireElevated();
    final state = control.status(_name);
    // Read before any file goes: the data directory the purge works on is
    // the one the service was configured with.
    final config = _tryReadConfig();
    if (purgeAccounts &&
        config == null &&
        File(layout.configFile).existsSync()) {
      // The purge works on the data directory the config names; guessing the
      // default could purge another one.
      throw YaguraException(
        'service_config_invalid',
        '${layout.configFile} exists but was not written by `yagurad service '
            'install`, so the data directory of the service is not known; '
            'nothing was changed. Remove the file by hand, or uninstall '
            'without --purge-accounts',
      );
    }
    final registered = state != ServiceStatus.notInstalled;
    if (!registered && !(purgeAccounts && config != null)) {
      throw _notInstalled();
    }
    if (purgeAccounts) {
      final running = await servers.runningServers();
      if (running.isNotEmpty) throw _serversRunning(running);
    }

    if (registered) {
      if (state != ServiceStatus.stopped) {
        await control.stop(layout);
        await _waitFor(ServiceStatus.stopped);
        if (purgeAccounts) {
          // A server may have started between the look above and the stop
          // (a remote start, an autostart); the stopped daemon cannot be
          // asked, so the probe reads its database.
          final List<String> late;
          try {
            late = await servers.runningServers();
          } on Object {
            // The service was stopped for this look; put it back.
            await _restart();
            rethrow;
          }
          if (late.isNotEmpty) {
            await _restart();
            throw _serversRunning(late, restarted: true);
          }
        }
      }
      await control.uninstall(layout);
    }
    await _removeApiRule();
    final removal = await _removeFiles();
    out.writeln(
      registered
          ? 'service $_name removed.'
          : 'service $_name was already removed from the service manager.',
    );
    for (final version in removal.versions) {
      out.writeln(
        'kept ${layout.versionDirectory(version)}: running game servers '
        'still execute from it. A reinstall of this version reuses it, and '
        'a service of another version deletes it when it starts once the '
        'servers are gone',
      );
    }
    for (final (path, why) in removal.files) {
      out.writeln('kept $path: $why; delete it by hand');
    }
    out.writeln(
      'The data directory, the service accounts and running game servers '
      'were left in place.',
    );

    if (purgeAccounts) {
      final outcomes = await purger.purge(dataDirectory: config?.dataDirectory);
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
              'removed yet (${stayed.first.reason}); once that is resolved '
              '(for a profile in use: once the processes using it have '
              'exited), run `yagurad service uninstall --purge-accounts` '
              'again',
        );
      }
    }
  }

  static String _problem(Object e) =>
      e is FirewallUnavailable ? e.message : '$e';

  /// Whether a daemon answers on the admin channel. Called while this
  /// service is not running (before its first start, after its stop), so an
  /// answer is another service's: the one daemon that holds the channel
  /// manages the firewall group, and this command leaves its rule alone.
  Future<bool> _anotherServiceManagesFirewall() async {
    try {
      await admin('status');
      return true;
    } on YaguraException {
      return false;
    }
  }

  /// Creates the API port rule. The service is installed either way: a
  /// firewall that cannot be used is a warning, and the daemon's reconciler
  /// creates the rule at a start where it can (design D11).
  Future<void> _ensureApiRule(int port) async {
    final rule = apiRule;
    if (rule == null) return;
    if (await _anotherServiceManagesFirewall()) {
      out.writeln(
        'note: another Yagura service is running and manages the firewall, '
        'so the rule $apiRuleName was not changed; that service owns the '
        'group Yagura (see docs/firewall.md)',
      );
      return;
    }
    try {
      await rule.ensure(port);
      out.writeln('firewall rule $apiRuleName allows tcp port $port');
    } on Object catch (e) {
      out.writeln(
        'warning: the firewall rule $apiRuleName for port $port is missing '
        '(firewall_unavailable: ${_problem(e)}). Remote devices cannot reach '
        'the daemon until the rule exists; the daemon creates it at a start '
        'where the Windows Firewall works',
      );
    }
  }

  /// Whether the install root is still the folder the install made: owned by
  /// Administrators, protected, with nobody else able to write in it. The
  /// firewall step puts a request file for PowerShell in it, which runs as an
  /// administrator.
  bool _rootStillProtected() {
    ProtectedDirectory? directory;
    try {
      if (FileSystemEntity.typeSync(layout.root, followLinks: false) !=
          FileSystemEntityType.directory) {
        return false;
      }
      directory = aclWriter.open(layout.root);
      return hasInstallRootProtection(directory.security());
    } on Object {
      return false;
    } finally {
      directory?.close();
    }
  }

  /// Removes the API port rule with the service. Servers and their rules stay
  /// (design D6). Another service that manages the firewall keeps the rule;
  /// a root that is no longer ours is not used.
  Future<void> _removeApiRule() async {
    final rule = apiRule;
    if (rule == null) return;
    if (!_rootStillProtected()) {
      out.writeln(
        'warning: the firewall rule $apiRuleName was not removed '
        '(firewall_unavailable: ${layout.root} is not the protected folder '
        'the install made, so no request is written there for PowerShell); '
        'delete the rule by hand in the group Yagura',
      );
      return;
    }
    if (await _anotherServiceManagesFirewall()) {
      out.writeln(
        'kept the firewall rule $apiRuleName: another Yagura service is '
        'running and manages the firewall',
      );
      return;
    }
    try {
      await rule.remove();
    } on Object catch (e) {
      out.writeln(
        'warning: the firewall rule $apiRuleName could not be removed '
        '(firewall_unavailable: ${_problem(e)}); delete it by hand in the '
        'group Yagura',
      );
    }
  }

  Future<void> _restart() async {
    await control.start(layout);
    await _waitFor(ServiceStatus.running);
  }

  YaguraException _serversRunning(
    List<String> running, {
    bool restarted = false,
  }) => YaguraException(
    'servers_running',
    restarted
        ? 'a game server started while the service stopped: '
              '${running.join(', ')}. The service was started again and '
              'nothing was removed. Stop the servers, then run '
              '--purge-accounts again'
        : '--purge-accounts needs every game server stopped, and these run: '
              '${running.join(', ')}. Stop them, then run it again; nothing '
              'was changed',
    details: {'servers': running},
  );

  /// Deletes the configuration, the wrapper, its logs and every version
  /// directory this service made, as far as it can. What stays is returned.
  Future<({List<String> versions, List<(String, String)> files})>
  _removeFiles() async {
    final versions = <String>[];
    final files = <(String, String)>[];
    final root = Directory(layout.root);
    if (!root.existsSync()) return (versions: versions, files: files);

    Future<void> remove(FileSystemEntity entity) async {
      final why = await _deleteWithRetry(entity);
      if (why != null) files.add((entity.path, why));
    }

    await remove(File(layout.configFile));
    await remove(File(layout.winswExecutable));
    // What the wrapper wrote: its logs folder, and files named after the
    // service. A file still open keeps its folder (best effort).
    final prefix = '${layout.serviceName}.';
    final List<FileSystemEntity> entries;
    try {
      entries = root.listSync(followLinks: false);
    } on FileSystemException catch (e) {
      files.add((layout.root, e.message));
      return (versions: versions, files: files);
    }
    for (final entity in entries) {
      final name = p.basename(entity.path);
      final isLogs =
          entity is Directory && name == p.basename(layout.logDirectory);
      final isWrapperFile = entity is File && name.startsWith(prefix);
      if (isLogs || isWrapperFile) await remove(entity);
    }
    // Only the directories this service's install made: the root may be
    // shared with another service or hold other software's versioned folders.
    for (final entity in entries) {
      final name = p.basename(entity.path);
      if (entity is! Directory ||
          !isVersionName(name) ||
          !layout.ownsVersionDirectory(name)) {
        continue;
      }
      try {
        layout.deleteVersionDirectory(name);
      } on FileSystemException {
        // A relay of a running server executes from it.
        versions.add(name);
      }
    }
    try {
      if (root.listSync().isEmpty) root.deleteSync();
    } on FileSystemException {
      // Reported by what stays in it.
    }
    return (versions: versions, files: files);
  }

  /// Deletes [entity]; a file that is locked for a moment (WinSW reports
  /// the service stopped a little before its process exits) is tried a few
  /// times. Returns why it stays, or null.
  Future<String?> _deleteWithRetry(FileSystemEntity entity) async {
    FileSystemException? last;
    for (var attempt = 0; attempt < 5; attempt++) {
      if (attempt > 0) await delay(pollInterval);
      try {
        if (entity.existsSync()) entity.deleteSync(recursive: true);
        return null;
      } on FileSystemException catch (e) {
        last = e;
      }
    }
    final os = last!.osError?.message.trim();
    return os == null || os.isEmpty ? last.message : os;
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
    // The bind goes into the command line unquoted.
    if (RegExp(r'[\s"%]').hasMatch(bind)) {
      throw YaguraException(
        'bind_invalid',
        'the bind "$bind" must not contain whitespace, a quote or a %',
      );
    }
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

  ServiceConfig? _tryReadConfig() {
    final file = File(layout.configFile);
    try {
      return file.existsSync()
          ? ServiceConfig.parse(file.readAsStringSync(), layout)
          : null;
    } on FileSystemException {
      return null;
    }
  }

  /// The paths go into a WinSW command line, and WinSW expands `%NAME%` in
  /// it; there is no way to write a literal percent sign.
  void _requirePlainPath(String what, String path) {
    if (!path.contains('%') && !path.contains('"')) return;
    throw YaguraException(
      'path_invalid',
      '$what "$path" contains a % or a quote, which the service wrapper '
          'would read as part of its own syntax; use another path',
    );
  }

  /// Refuses a root below a folder that a user who is not an administrator
  /// could replace, or off a local drive letter. Reads only the folders above
  /// the root.
  void _checkAncestors() {
    final root = layout.root;
    final problems = ancestorProblems(root, inspector);
    if (problems.isNotEmpty) {
      throw YaguraException(
        'install_dir_not_protected',
        'cannot install into $root: a user who is not an administrator could '
            'replace a folder above it (${problems.join('; ')}). Use a folder '
            'below %ProgramFiles%, or one that only administrators own and '
            'can change',
      );
    }
  }

  /// Checks the folders above the install root, then makes sure the root is
  /// one only administrators can change, before anything is copied in (the
  /// files run as LocalSystem):
  ///
  ///  * a root that does not exist is created with its owner (Administrators)
  ///    and its DACL (SYSTEM and Administrators full control, Users read and
  ///    execute, nothing inherited) in the same call, so there is no moment
  ///    at which anyone else has access to it;
  ///  * a root that exists is used only if it already has exactly that owner
  ///    and DACL, read on the handle the install then works through. Whoever
  ///    made a folder owns it and may hold a handle that can still change its
  ///    permissions, and protecting it afterwards does not revoke that, so an
  ///    existing folder is never adopted, empty or not. Only an install of
  ///    this tool leaves that owner and DACL on a folder.
  ///
  /// Anything else is refused, with nothing changed or deleted.
  void _protectRoot() {
    final root = layout.root;
    final exists =
        FileSystemEntity.typeSync(root, followLinks: false) !=
        FileSystemEntityType.notFound;
    ProtectedDirectory? directory;
    try {
      if (exists) {
        directory = aclWriter.open(root);
        if (!hasInstallRootProtection(directory.security())) {
          throw _notProtected(
            'it was not made by an install of yagurad, and a folder that '
            'someone else made can be changed through a handle they keep',
          );
        }
      } else {
        try {
          directory = aclWriter.create(
            root,
            installRootDaclSddl,
            ownerSid: administratorsSid,
          );
        } on PathExists {
          throw _notProtected('it was created by someone else just now');
        }
        if (!hasInstallRootProtection(directory.security())) {
          throw _notProtected(
            'it does not carry the owner and permissions it was created with',
          );
        }
      }
    } on PathRefused catch (e) {
      throw exists
          ? _notProtected(e.why)
          : YaguraException('install_failed', 'cannot create $root: ${e.why}');
    } on YaguraException {
      rethrow;
    } on Object catch (e) {
      throw YaguraException('install_failed', 'cannot create $root: $e');
    } finally {
      directory?.close();
    }
  }

  YaguraException _notProtected(String why) => YaguraException(
    'install_dir_not_protected',
    'cannot use ${layout.root}: $why. Use a folder that does not exist yet '
        '(the install creates it protected); nothing in it was changed',
  );

  void _protect(String path) {
    final ProtectedDirectory directory;
    try {
      directory = aclWriter.open(path);
    } on Object catch (e) {
      throw YaguraException(
        'install_failed',
        'cannot protect $path: ${e is PathRefused ? e.why : e}',
      );
    }
    try {
      directory.writeDacl(installRootDaclSddl, ownerSid: administratorsSid);
    } on Object catch (e) {
      throw YaguraException('install_failed', 'cannot protect $path: $e');
    } finally {
      directory.close();
    }
  }

  /// Puts the bundle in the version directory. A directory this service's
  /// install made earlier is reused: relays of running servers execute from
  /// it (a reinstall after `uninstall`), so nothing in it is deleted, and
  /// only the files that differ from the bundle are written.
  void _copyVersion(String version) {
    final directory = layout.versionDirectory(version);
    try {
      if (Directory(directory).existsSync()) {
        final owner = layout.markerOwner(version);
        if (owner != null && owner != _name) {
          throw YaguraException(
            'install_failed',
            '$directory was made by the install of service $owner; install '
                'this service into another --install-dir',
          );
        }
        if (owner == null && Directory(directory).listSync().isNotEmpty) {
          throw YaguraException(
            'install_failed',
            '$directory exists and was not made by `yagurad service '
                'install`; remove it or use another --install-dir',
          );
        }
      } else {
        Directory(directory).createSync(recursive: true);
      }
      _protect(directory);
      layout.markVersionDirectory(version);
      _bundle.copyTo(directory);
    } on FileSystemException catch (e) {
      throw YaguraException(
        'install_failed',
        'cannot copy the bundle to $directory: ${e.message} ${e.path ?? ''}'
            .trimRight(),
      );
    }
  }

  /// Copies WinSW as `<service>.exe`. An existing file is deleted first, so
  /// the copy has the protected folder's ACL and not that of a file someone
  /// else made.
  void _copyWrapper() {
    final target = File(layout.winswExecutable);
    if (target.existsSync()) target.deleteSync();
    File(_bundle.winswExecutable).copySync(layout.winswExecutable);
  }

  /// Writes [text] through a temporary file, so a reader (WinSW at service
  /// start) never sees half of it.
  void _write(String path, String text) {
    Directory(p.dirname(path)).createSync(recursive: true);
    // A new file each time: an old one keeps its owner and permissions.
    final temporary = File('$path.tmp');
    if (temporary.existsSync()) temporary.deleteSync();
    temporary.createSync(exclusive: true);
    temporary.writeAsStringSync(text, flush: true);
    temporary.renameSync(path);
  }

  void _removeInstallFiles(
    ServiceConfig config, {
    required bool removeRoot,
    required bool removeVersion,
  }) {
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
    // A version directory that was there before may be in use.
    if (removeVersion) {
      tryDelete(Directory(layout.versionDirectory(config.version)));
    }
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
