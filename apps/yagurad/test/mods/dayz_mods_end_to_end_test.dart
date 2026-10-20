import 'dart:async';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../fixtures/fake_workshop_api.dart';
import '../support/api_support.dart';
import '../support/content_support.dart';
import '../support/daemon_support.dart';
import '../support/mods_support.dart';
import '../support/secret_support.dart';

// The shipped `plugins/dayz`, run in-process: the fake SteamCMD writes the
// workshop content, the fake Web API answers the item lookups, and the fake
// process host stands in for `DayZServer_x64.exe`. Covers exit criterion 4 and
// the agent side of exit criterion 3 of the M3 roadmap.

const _adminPassword = 'Zr0-admin-horse';
const _rconPassword = 'Zr0-rcon-horse';
const _firstVersion = '1700000000';
const _newVersion = '1700500000';

/// Twelve workshop mods, in the order the admin loads them, with the role of
/// each. Titles are plain so the staged name is `@` and the title.
const _mods = <(String id, String title, String role)>[
  ('2000001', 'CF', 'client'),
  ('2000002', 'Community-Online-Tools', 'client'),
  ('2000003', 'VPPAdminTools', 'server'),
  ('2000004', 'Code-Lock', 'client'),
  ('2000005', 'BaseBuildingPlus', 'client'),
  ('2000006', 'Trader', 'client'),
  ('2000007', 'Expansion-Core', 'client'),
  ('2000008', 'Dabs-Framework', 'client'),
  ('2000009', 'BuilderItems', 'client'),
  ('2000010', 'Banking', 'server'),
  ('2000011', 'SNAFU-Weapons', 'client'),
  ('2000012', 'Ear-Plugs', 'server'),
];

String _name(String title) => '@$title';

List<String> _names(String role) => [
  for (final (_, title, r) in _mods)
    if (r == role) _name(title),
];

class _Rig {
  _Rig._(this.env, this.workshop, this.steam, this.daemon, this.api);

  final TestEnv env;
  final FakeWorkshopApi workshop;
  final ModsSteam steam;
  final Daemon daemon;
  final ApiHarness api;

  static Future<_Rig> start() async {
    final env = TestEnv();
    // The plugin as it ships: the manifest and its templates.
    final shipped = Directory(p.absolute('..', '..', 'plugins', 'dayz'));
    for (final entity in shipped.listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: shipped.path);
      File(p.join(env.pluginsDir, 'dayz', relative))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(entity.readAsBytesSync());
    }
    final workshop = await FakeWorkshopApi.start();
    addTearDown(workshop.close);
    for (final (id, title, _) in _mods) {
      workshop.add(
        FakeWorkshopItem(
          id,
          title: title,
          fileSize: 4096,
          timeUpdated: int.parse(_firstVersion),
        ),
      );
    }
    final steam = ModsSteam(p.join(env.data, 'steamcmd'));
    final daemon = await env.start(
      steamService: steam,
      workshopEndpoint: workshop.endpoint,
      secretProtector: FakeSecretProtector(devSid),
    );
    final api = await ApiHarness.start(env, daemon: daemon);
    // A Steam account that is ready: DayZ Server needs one to install.
    final db = sqlite3.open(p.join(env.data, 'yagura.db'));
    addTearDown(db.close);
    db.execute(
      "INSERT INTO steam_accounts (id, username, status, created_at) "
      "VALUES ('acct0', 'srvadmin', 'ready', 1)",
    );
    // The server writes its ready line to the profile's RPT once it runs.
    env.process
      ..readyLine = null
      ..onLaunch = (_) {
        File(
            p.join(
              env.process.launches.last.workingDirectory,
              'profiles',
              'DayZServer_x64_run${env.process.launches.length}.RPT',
            ),
          )
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('Dedicated host created.\n');
      };
    return _Rig._(env, workshop, steam, daemon, api);
  }

  /// A DayZ instance with the twelve mods set, installed and stopped.
  Future<Instance> instance({
    String name = 'Chernarus',
    int port = 2302,
  }) async {
    final created = await daemon.instances.create(
      CreateInstanceRequest(
        pluginId: 'dayz',
        name: name,
        settings: {'hostname': name, 'maxPlayers': 40},
        ports: {'game': port},
        steamAccountId: 'acct0',
      ),
    );
    final installed = await daemon.operations.whenDone(
      daemon.instances.install(created.id).id,
    );
    expect(
      installed.status,
      OperationStatus.succeeded,
      reason: installed.resultMessage,
    );
    daemon.instances.setSecret(created.id, 'adminPassword', _adminPassword);
    daemon.instances.setSecret(created.id, 'rconPassword', _rconPassword);
    final stopped = daemon.instances.get(created.id);
    await api.mods.setMods(
      pb.SetModsRequest(
        instanceId: stopped.id,
        expectedRevision: Int64(stopped.revision),
        mods: [
          for (final (id, _, role) in _mods)
            pb.ModRef(source: 'steam_workshop', itemId: id, role: role),
        ],
      ),
    );
    return daemon.instances.get(created.id);
  }

  /// One Start: the fake server is launched and its RPT says it is ready.
  Future<Operation> startServer(Instance instance) async {
    final done = daemon.operations.whenDone(
      daemon.instances.start(instance.id).id,
    );
    var finished = false;
    unawaited(done.whenComplete(() => finished = true));
    // The log hub of the tests polls only when told to.
    while (!finished) {
      await daemon.logs.pollNow(instance.id);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return done;
  }

  Future<Operation> stop(Instance instance) => runStop(daemon, instance.id);

  Future<List<pb.Mod>> listed(Instance instance) async =>
      (await api.mods.listMods(pb.ListModsRequest(instanceId: instance.id)))
          .mods;

  String link(Instance instance, String title) =>
      p.join(instance.directory, 'server', _name(title));

  String versionDir(String id, String version) => p.join(
    daemon.dataDirectory.contentPath,
    'steam_workshop',
    dayzWorkshopApp,
    id,
    version,
  );

  List<String> get launchArgs => env.process.launches.last.args;

  Future<Operation> checkUpdates(Instance instance) async {
    final op = await api.mods.checkModUpdates(
      pb.CheckModUpdatesRequest(instanceId: instance.id),
    );
    return daemon.operations.whenDone(op.id);
  }

  Future<Operation> updateMods(Instance instance) async {
    final op = await api.mods.updateMods(
      pb.UpdateModsRequest(instanceId: instance.id),
    );
    return daemon.operations.whenDone(op.id);
  }
}

void main() {
  test('twelve_mods_to_a_launched_server_in_one_start', () async {
    final rig = await _Rig.start();
    final instance = await rig.instance();

    // Installing used the account and the server app.
    final install = rig.steam.runs.single;
    expect(install.appId, 223350);
    expect(install.account, 'acct0');
    expect(rig.steam.workshopRuns, isEmpty, reason: 'nothing downloaded yet');
    expect(await rig.listed(instance), hasLength(12));

    final done = await rig.startServer(instance);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(rig.daemon.instances.get(instance.id).state, InstanceState.running);

    // The twelve items came from the DayZ workshop app, through the account.
    expect(rig.steam.workshopRuns.map((r) => r.workshopAppId).toSet(), {
      221100,
    });
    expect(rig.steam.workshopRuns.map((r) => r.account).toSet(), {'acct0'});
    expect(
      <String>{for (final run in rig.steam.downloaded) ...run},
      {for (final (id, _, _) in _mods) id},
    );

    // One link per mod, in the shared content store.
    for (final (id, title, _) in _mods) {
      expect(
        linksTo(rig.link(instance, title), rig.versionDir(id, _firstVersion)),
        isTrue,
        reason: '${_name(title)} links to the content store',
      );
    }
    final staged = [for (final m in await rig.listed(instance)) m.stagedName];
    expect(staged, [for (final (_, title, _) in _mods) _name(title)]);

    // One key per mod in server/keys/ (copies, not links).
    final keys = Directory(p.join(instance.directory, 'server', 'keys'));
    expect(
      [for (final f in keys.listSync()) p.basename(f.path)]..sort(),
      [for (final (id, _, _) in _mods) '$id.bikey']..sort(),
    );
    for (final (id, _, _) in _mods) {
      final key = p.join(keys.path, '$id.bikey');
      expect(isLink(key), isFalse);
      expect(File(key).readAsBytesSync(), List.filled(16, 3));
    }

    // The launch: working directory, arguments and the mod order.
    final launch = rig.env.process.launches.single;
    expect(launch.workingDirectory, p.join(instance.directory, 'server'));
    expect(p.basename(launch.executable), 'DayZServer_x64.exe');
    expect(launch.args, [
      '-config=yagura/serverDZ.cfg',
      '-BEpath=yagura/battleye',
      '-profiles=profiles',
      '-port=2302',
      '-steamQueryPort=2305',
      '-mod=${_names('client').join(';')}',
      '-serverMod=${_names('server').join(';')}',
    ]);
    expect(launch.args.join(' '), isNot(contains(_adminPassword)));

    // The bound files, created from the plugin's templates.
    final cfg = File(
      p.join(instance.directory, 'server', 'yagura', 'serverDZ.cfg'),
    ).readAsStringSync();
    expect(cfg, contains('hostname = "Chernarus";'));
    expect(cfg, contains('maxPlayers = 40;'));
    expect(cfg, contains('verifySignatures = 2;'));
    expect(cfg, contains('passwordAdmin = "$_adminPassword";'));
    expect(cfg, contains('password = "";'), reason: 'unset secret kept');
    expect(cfg, contains('template = "dayzOffline.chernarusplus"'));
    final be = File(
      p.join(
        instance.directory,
        'server',
        'yagura',
        'battleye',
        'BEServer_x64.cfg',
      ),
    ).readAsStringSync();
    expect(be, contains('RConPort 2306'));
    expect(be, contains('RConPassword $_rconPassword'));
    expect(be, contains('MaxPing 350'));
    // The depot's own file is not where the bindings write.
    expect(
      File(p.join(instance.directory, 'server', 'serverDZ.cfg')).existsSync(),
      isFalse,
    );
  });

  test('a_second_instance_shares_one_content_directory', () async {
    final rig = await _Rig.start();
    final first = await rig.instance(name: 'Chernarus');
    expect((await rig.startServer(first)).status, OperationStatus.succeeded);
    final downloads = rig.steam.workshopRuns.length;

    final second = await rig.instance(name: 'Livonia', port: 2402);
    final done = await rig.startServer(second);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(
      rig.steam.workshopRuns,
      hasLength(downloads),
      reason: 'the version is in the store: nothing is downloaded again',
    );
    expect(rig.launchArgs, contains('-port=2402'));
    expect(rig.launchArgs, contains('-steamQueryPort=2405'));
    final store = Directory(
      p.join(
        rig.daemon.dataDirectory.contentPath,
        'steam_workshop',
        dayzWorkshopApp,
      ),
    );
    expect(
      store.listSync().whereType<Directory>(),
      hasLength(12),
      reason: 'one directory per item',
    );
    for (final (id, title, _) in _mods) {
      final target = rig.versionDir(id, _firstVersion);
      expect(Directory(target).parent.listSync(), hasLength(1));
      expect(linksTo(rig.link(first, title), target), isTrue);
      expect(linksTo(rig.link(second, title), target), isTrue);
      expect(
        resolvedTarget(rig.link(second, title)),
        resolvedTarget(rig.link(first, title)),
        reason: '${_name(title)} is the same directory for both',
      );
    }
  });

  test('a_mod_update_re_links_only_the_changed_mod', () async {
    final rig = await _Rig.start();
    final instance = await rig.instance();
    expect((await rig.startServer(instance)).status, OperationStatus.succeeded);
    expect((await rig.stop(instance)).status, OperationStatus.succeeded);
    final before = {
      for (final (_, title, _) in _mods)
        title: resolvedTarget(rig.link(instance, title)),
    };
    final argsBefore = List.of(rig.launchArgs);
    final downloads = rig.steam.workshopRuns.length;

    // One of the twelve is updated on the workshop.
    const changed = ('2000006', 'Trader');
    rig.workshop.items[changed.$1]!.timeUpdated = int.parse(_newVersion);
    expect(
      (await rig.checkUpdates(instance)).status,
      OperationStatus.succeeded,
    );
    expect(
      [
        for (final m in await rig.listed(instance))
          if (m.updateAvailable) m.itemId,
      ],
      [changed.$1],
    );
    final updated = await rig.updateMods(instance);

    expect(
      updated.status,
      OperationStatus.succeeded,
      reason: updated.resultMessage,
    );
    expect(rig.steam.workshopRuns, hasLength(downloads + 1));
    expect(rig.steam.downloaded.last, [changed.$1]);
    for (final (id, title, _) in _mods) {
      final link = rig.link(instance, title);
      if (id == changed.$1) {
        expect(linksTo(link, rig.versionDir(id, _newVersion)), isTrue);
      } else {
        expect(
          resolvedTarget(link),
          before[title],
          reason: '${_name(title)} is not re-linked',
        );
      }
    }
    // The server starts again with the same arguments.
    final done = await rig.startServer(instance);
    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(rig.launchArgs, argsBefore);
  });
}
