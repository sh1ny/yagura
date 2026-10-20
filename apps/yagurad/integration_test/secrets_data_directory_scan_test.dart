@Tags(['windows'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/files/instance_fs.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/process/process.dart';

import '../test/config/config_support.dart';
import '../test/support/daemon_support.dart';
import '../test/support/secret_support.dart';
import '../test/support/steam_account_support.dart';
import '../test/support/steam_support.dart';

// Secret values live only in the OS-backed secret store (daemon-security,
// "Secrets never leave the daemon"; design D3). This runs a whole
// install-start-stop workflow in an in-process dev-mode daemon (the real fake
// SteamCMD, temp directories, nothing elevated) and reads every byte of every
// file the daemon and the instance left behind.

/// Values with characters outside ASCII, so that the UTF-8 and UTF-16 forms
/// differ, and long enough to rule out chance hits.
const secrets = {
  'Friends': 'pässwörd-Ünï-7f3a9c-never-on-disk',
  'Family': 'sécrét-ß-91d2e4-never-on-disk',
};

/// The byte forms a secret could be written in.
Map<String, List<int>> encodingsOf(String value) => {
  'UTF-8': utf8.encode(value),
  'UTF-16LE': [
    for (final unit in value.codeUnits) ...[unit & 0xFF, unit >> 8],
  ],
  'UTF-16BE': [
    for (final unit in value.codeUnits) ...[unit >> 8, unit & 0xFF],
  ],
  'Latin-1': latin1.encode(value),
};

bool containsBytes(Uint8List haystack, List<int> needle) {
  final first = needle.first;
  for (
    var i = haystack.indexOf(first);
    i >= 0 && i <= haystack.length - needle.length;
    i = haystack.indexOf(first, i + 1)
  ) {
    var match = true;
    for (var j = 1; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

/// Reads every file under [roots] (links not followed) and returns what was
/// scanned and where a secret in any encoding was found. [allowed] names, for
/// a value, the one file that may hold it (a secret bound into a config file).
({List<String> scanned, List<String> leaks}) scan(
  Iterable<String> roots,
  Iterable<String> values, {
  Map<String, String> allowed = const {},
}) {
  final scanned = <String>[];
  final leaks = <String>[];
  final forms = {for (final value in values) value: encodingsOf(value)};
  for (final root in roots) {
    for (final entity in Directory(
      root,
    ).listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      scanned.add(entity.path);
      final bytes = entity.readAsBytesSync();
      for (final MapEntry(key: value, value: encodings) in forms.entries) {
        if (allowed[value] case final path? when p.equals(path, entity.path)) {
          continue;
        }
        for (final MapEntry(key: name, value: needle) in encodings.entries) {
          if (containsBytes(bytes, needle)) {
            leaks.add('${entity.path}: "$value" as $name');
          }
        }
      }
    }
  }
  return (scanned: scanned, leaks: leaks);
}

void main() {
  test('the_scan_finds_a_secret_in_every_encoding', () {
    final dir = Directory.systemTemp.createTempSync('yagurad_scan_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final value = secrets.values.first;
    final forms = encodingsOf(value);
    for (final MapEntry(:key, value: bytes) in forms.entries) {
      File(p.join(dir.path, key)).writeAsBytesSync([0, 1, 2, ...bytes, 3]);
    }

    final found = scan([dir.path], [value]);

    expect(found.leaks, hasLength(forms.length));
  });

  test('data_directory_scan', () async {
    final env = TestEnv();
    env.installValheim();
    final steam = SteamHarness(env);
    final daemon = await env.start(
      steamService: steam.service,
      secretProtector: FakeSecretProtector(devSid),
    );

    final instances = <Instance>[];
    var port = 2456;
    for (final name in secrets.keys) {
      final created = await createValheim(
        daemon,
        name: name,
        ports: {'game': port},
      );
      port += 10;
      daemon.instances.setSecret(created.id, 'password', secrets[name]!);
      final installed = await daemon.operations.whenDone(
        daemon.instances.install(created.id).id,
      );
      expect(
        installed.status.name,
        'succeeded',
        reason: installed.resultMessage,
      );
      final started = await runStart(daemon, created.id);
      expect(started.status.name, 'succeeded', reason: started.resultMessage);
      expect(daemon.instances.get(created.id).state, InstanceState.running);
      instances.add(daemon.instances.get(created.id));
    }
    expect(steam.appRuns(), isNotEmpty, reason: 'the fake SteamCMD ran');

    List<String> roots() => {
      env.data,
      for (final instance in instances) instance.directory,
    }.toList();

    // While the daemon runs (the database may sit in its write-ahead log)...
    final running = scan(roots(), secrets.values);
    expect(
      running.scanned.any((f) => f.endsWith('.db') || f.contains('yagura')),
      isTrue,
      reason: 'the scan reached the daemon database',
    );
    expect(
      running.scanned.where((f) => f.endsWith('instance.json')),
      isNotEmpty,
      reason: 'the scan reached the portable instance files',
    );

    for (final instance in instances) {
      final stopped = await runStop(daemon, instance.id);
      expect(stopped.status.name, 'succeeded', reason: stopped.resultMessage);
    }

    // ...after the stops, and once the daemon closed and flushed everything.
    expect(scan(roots(), secrets.values).leaks, isEmpty);
    await env.closeDaemons();
    final closed = scan(roots(), secrets.values);
    expect(closed.scanned, isNotEmpty);
    expect(closed.leaks, isEmpty, reason: closed.leaks.join('\n'));
    expect(running.leaks, isEmpty, reason: running.leaks.join('\n'));
  });

  test('data_directory_scan_with_steam_accounts_and_bound_secrets', () async {
    // Passwords with characters outside ASCII, a game server login token and
    // a secret setting bound into a config file, per instance.
    const accounts = {
      // user: (password, remembered)
      'alice': ('pässwörd-Ünï-A1b2c3-steam-never-on-disk', true),
      'bob': ('sécrét-ß-D4e5f6-steam-never-on-disk', false),
    };
    const gslts = ['GSLT-Ünï-0A1B2C3D-never-on-disk', 'GSLT-ß-9Z8Y7X6W-never'];
    const rcons = ['rcön-Ünï-1d2c3b-never-in-a-log', 'rcön-ß-4e5f6a-never-in'];
    const boundFile = 'battleye/BEServer_x64.cfg';

    final rig = await AccountRig.start(
      realSnapshots: true,
      editPlugin: (env) {
        env.editValheim(
          '  login: account\n',
          '  login: account\n  gslt: { setting: gslt, required: true }\n',
        );
        env.editValheim(
          '    label: Server password\n    group: General\n',
          '    label: Server password\n    group: General\n'
              '  gslt:\n    type: secret\n    label: Game Server Login Token\n'
              '  rconPassword:\n    type: secret\n    label: RCON password\n',
        );
        env.editValheim(
          '    - -batchmode\n',
          '    - -batchmode\n    - "-gslt={{secrets.gslt}}"\n',
        );
        final binding = bindingYaml(
          file: boundFile,
          format: 'kv',
          key: 'RConPassword',
          setting: 'rconPassword',
          create: true,
          template: 'templates/BEServer_x64.cfg',
        );
        env.editValheim(
          'launch:\n  args:',
          'bindings:\n$binding\nlaunch:\n  args:',
        );
        File(p.join(env.pluginsDir, 'valheim', 'templates', 'BEServer_x64.cfg'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('RConPassword changeme\nRConPort 2310\n');
      },
    );
    final env = rig.env;
    final daemon = rig.daemon;
    final values = <String>[
      for (final (password, _) in accounts.values) password,
      ...gslts,
      ...rcons,
    ];
    // Where each bound secret is meant to be written.
    final bound = <String, String>{};

    final instances = <Instance>[];
    var index = 0;
    var port = 2456;
    for (final MapEntry(key: user, value: (password, remember))
        in accounts.entries) {
      // The account is added through the fake SteamCMD with a known password.
      final account = await rig.addReady(
        user,
        password: password,
        remember: remember,
      );
      expect(account.status, 'ready');
      // Later runs log in with the cached credentials, or with the remembered
      // password.
      rig.steam.script.rules([
        loginRule(1, 'cached_ok'),
        loginRule(2, 'code_accepted'),
      ]);
      final created = await daemon.instances.create(
        CreateInstanceRequest(
          pluginId: 'valheim',
          name: user,
          settings: valheimSettings(name: user),
          ports: {'game': port},
          steamAccountId: account.id,
        ),
      );
      port += 10;
      daemon.instances.setSecret(created.id, 'gslt', gslts[index]);
      daemon.instances.setSecret(created.id, 'rconPassword', rcons[index]);
      final installed = await daemon.operations.whenDone(
        daemon.instances.install(created.id).id,
      );
      expect(
        installed.status.name,
        'succeeded',
        reason: installed.resultMessage,
      );
      // A save, so that the update takes a snapshot of it.
      File(p.join(created.directory, 'save', 'world.db'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('world of $user');
      final updated = await daemon.operations.whenDone(
        daemon.instances.update(created.id).id,
      );
      expect(updated.status.name, 'succeeded', reason: updated.resultMessage);
      final started = await runStart(daemon, created.id);
      expect(started.status.name, 'succeeded', reason: started.resultMessage);
      final instance = daemon.instances.get(created.id);
      expect(instance.state, InstanceState.running);
      final file = File(p.join(instance.directory, boundFile));
      expect(file.readAsStringSync(), contains(rcons[index]));
      bound[rcons[index]] = p.normalize(file.path);
      // The fake process host writes no run files, so write the ones the
      // real supervisor writes for this launch (argument slots, no values).
      final launch = env.process.launches.last;
      expect(launch.secrets['gslt'], gslts[index]);
      RunFiles(
        p.join(instance.directory, '.yagura', 'run', 'scan-run'),
        fs: InstanceFs(instance.directory),
      ).writeLaunch(launch);
      instances.add(instance);
      index++;
    }
    expect(rig.steam.appRuns(), isNotEmpty, reason: 'the fake SteamCMD ran');
    expect(
      rig.loginArguments().expand((args) => args),
      containsAll([for (final (password, _) in accounts.values) password]),
      reason: 'the fake SteamCMD was given the passwords',
    );
    expect(rig.accountInstallations(), hasLength(accounts.length));

    List<String> roots() => {
      env.data,
      for (final instance in instances) instance.directory,
    }.toList();

    // The accepted location of a bound secret is its own file: it is there,
    // and nowhere else.
    for (final MapEntry(key: value, value: path) in bound.entries) {
      expect(
        scan(roots(), [value]).leaks.map((l) => l.split(': "').first).toSet(),
        {path},
        reason: 'only the bound file holds "$value"',
      );
    }

    void expectNoLeaks(String when) {
      final found = scan(roots(), values, allowed: bound);
      expect(found.leaks, isEmpty, reason: '$when:\n${found.leaks.join('\n')}');
      void reached(String what, bool Function(String path) test) => expect(
        found.scanned.any(test),
        isTrue,
        reason: 'the scan reached $what',
      );
      String rel(String path) => p.relative(path, from: env.root.path);
      reached('the daemon database', (f) => f.endsWith('.db'));
      reached('the account installations', (f) {
        final parts = p.split(rel(f));
        return parts.contains('steamcmd') &&
            parts.contains(rig.accountInstallations().first);
      });
      reached('the snapshots', (f) => p.split(rel(f)).contains('snapshots'));
      reached('the run files', (f) => p.split(rel(f)).contains('run'));
      reached('the instance files', (f) => p.basename(f) == 'instance.json');
    }

    expectNoLeaks('while the daemon runs');
    for (final instance in instances) {
      final stopped = await runStop(daemon, instance.id);
      expect(stopped.status.name, 'succeeded', reason: stopped.resultMessage);
    }
    expectNoLeaks('after the stops');
    await env.closeDaemons();
    expectNoLeaks('after the daemon closed');
  });
}
