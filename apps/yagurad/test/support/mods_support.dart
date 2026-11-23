import 'dart:async';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagura_proto/yagura_proto.dart' as pb;
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/mods/mod_check_schedule.dart';
import 'package:yagurad/src/mods/stage_link.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/steam/steam.dart';

import '../fixtures/fake_workshop_api.dart';
import 'api_support.dart';
import 'content_support.dart';
import 'daemon_support.dart';

/// Two workshop mods of DayZ (ids as on the workshop).
const vppMod = '1828439124';
const thirdMod = '1564026768';

/// The `mods` section and launch arguments of a DayZ-like plugin (workshop
/// source, links, key files, two roles).
const workshopModsSection = '''
mods:
  source: steam_workshop
  workshop_app_id: 221100
  stage: link
  stage_dir: server
  link_name: "@{{mod.name_safe}}"
  copy_fallback: true
  keys:
    - { from: "**/*.bikey", to: server/keys/ }
  roles: [client, server]
''';

const workshopModsLaunch = '''
    - join: { list: mods.client, separator: ";", prefix: "-mod=" }
    - join: { list: mods.server, separator: ";", prefix: "-serverMod=" }
''';

/// The `mods` section of a plugin whose server fetches its own mods.
const serverManagedModsSection = '''
mods:
  source: server_managed
  stage: none
  roles: [server]
''';

const serverManagedModsLaunch = '''
    - join: { list: mods.server, separator: ",", prefix: "-mods=" }
''';

/// The Valheim fixture's manifest with a `mods` section and the launch
/// arguments that carry the role lists.
String moddedValheimManifest({
  String mods = workshopModsSection,
  String launch = workshopModsLaunch,

  /// More top-level sections (bindings...), placed before `stop:`.
  String extra = '',
}) {
  final base = File(p.join(valheimFixture, 'plugin.yaml'))
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  const stop = '\nstop:\n';
  const tail = '    - -public\n    - "0"\n';
  expect(base, contains(stop), reason: 'fixture edit target');
  expect(base, contains(tail), reason: 'fixture edit target');
  return base
      .replaceFirst(stop, '\n$mods$extra$stop')
      .replaceFirst(tail, '$tail$launch');
}

/// Installs the plugin `valheim` with mods into [env]'s plugin directory.
void installModdedValheim(TestEnv env, {String? manifest, String? hooks}) {
  final dir = Directory(p.join(env.pluginsDir, 'valheim'))
    ..createSync(recursive: true);
  File(p.join(dir.path, 'plugin.yaml'))
      .writeAsStringSync(manifest ?? moddedValheimManifest());
  if (hooks != null) {
    File(p.join(dir.path, 'hooks.js')).writeAsStringSync(hooks);
  }
}

/// A Steam service for mod tests: installs succeed at once, and a workshop run
/// writes what SteamCMD would have downloaded under the installation of its
/// account (or `anonymous`), so the content store publishes it.
class ModsSteam extends FakeSteamService {
  ModsSteam(this.root);

  /// `<data>/steamcmd`.
  final String root;

  /// The files of an item (relative path to bytes); an item without an entry
  /// gets `meta.cpp`, `keys/<id>.bikey` and `addons/<id>.pbo`.
  final files = <String, Map<String, List<int>>>{};

  /// Items whose download fails with this error.
  final failures = <String, YaguraException>{};

  /// When set, a workshop run waits for it (or for cancellation) before it
  /// writes its items.
  Completer<void>? workshopGate;

  /// How many workshop runs are between their start and their end.
  var workshopRunning = 0;
  final _builds = <String, int>{};

  /// The items of every workshop run, in order.
  List<List<String>> get downloaded => [
    for (final run in workshopRuns) run.items,
  ];

  @override
  Future<List<SteamWorkshopItemResult>> downloadWorkshopItems(
    SteamWorkshopRequest request,
    SteamRunReporter reporter,
    CancelToken cancel,
  ) async {
    workshopRuns.add(request);
    workshopRunning++;
    try {
      reporter.step('download');
      reporter.progress(percent: 10, bytesDone: 10, bytesTotal: 100);
      if (workshopGate case final gate?) {
        await Future.any([gate.future, cancel.whenCancelled]);
        cancel.throwIfCancelled();
      }
      final installation = request.account ?? 'anonymous';
      final results = <SteamWorkshopItemResult>[];
      for (final item in request.items) {
        if (failures[item] case final error?) {
          results.add(SteamWorkshopItemResult(item, error));
          continue;
        }
        final dir = Directory(
          p.join(
            root,
            installation,
            'steamapps',
            'workshop',
            'content',
            '${request.workshopAppId}',
            item,
          ),
        );
        if (dir.existsSync()) dir.deleteSync(recursive: true);
        final build = _builds[item] = (_builds[item] ?? 0) + 1;
        final content =
            files[item] ??
            {
              'meta.cpp': 'protocol = 1;\npublishedid = $item;\n'.codeUnits,
              'keys/$item.bikey': List.filled(16, 3),
              'addons/$item.pbo': List.filled(64, 7),
            };
        for (final MapEntry(:key, :value) in {
          ...content,
          'build.txt': '$build'.codeUnits,
        }.entries) {
          File(p.join(dir.path, key))
            ..createSync(recursive: true)
            ..writeAsBytesSync(value);
        }
        results.add(SteamWorkshopItemResult(item));
      }
      return results;
    } finally {
      workshopRunning--;
    }
  }
}

/// A mod to set: item, role and source.
class ModSpec {
  const ModSpec(
    this.item, {
    this.role = 'client',
    this.source = 'steam_workshop',
  });

  final String item;
  final String role;
  final String source;
}

/// A daemon with a DayZ-like plugin behind a loopback API, the fake Steam Web
/// API and a Steam service that writes workshop content.
class ModsRig {
  ModsRig._(
    this.env,
    this.workshop,
    this.steam,
    this._schedule,
    this._stageLink,
  );

  final TestEnv env;
  final FakeWorkshopApi workshop;
  final ModsSteam steam;
  ModCheckSchedule _schedule;
  final StageLinkCreator _stageLink;
  late Daemon daemon;
  late ApiHarness grpc;

  pb.ModsClient get mods => grpc.mods;

  /// [manifest] and [hooks] replace the plugin's (the default is
  /// [moddedValheimManifest]).
  static Future<ModsRig> start({
    String? manifest,
    String? hooks,
    ModCheckSchedule schedule = const ModCheckSchedule.off(),
    StageLinkCreator stageLink = defaultStageLink,
    TestEnv? env,
  }) async {
    final testEnv = env ?? TestEnv();
    installModdedValheim(testEnv, manifest: manifest, hooks: hooks);
    final workshop = await FakeWorkshopApi.start();
    addTearDown(workshop.close);
    final steam = ModsSteam(p.join(testEnv.data, 'steamcmd'));
    final rig = ModsRig._(testEnv, workshop, steam, schedule, stageLink);
    rig.daemon = await rig._launch();
    rig.grpc = await ApiHarness.start(testEnv, daemon: rig.daemon);
    return rig;
  }

  Future<Daemon> _launch() => env.start(
    steamService: steam,
    workshopEndpoint: workshop.endpoint,
    modCheckSchedule: _schedule,
    stageLink: _stageLink,
  );

  /// Ends the daemon the way a killed process ends and starts another on the
  /// same data directory, with [schedule] for the update check when given.
  Future<void> restart({ModCheckSchedule? schedule}) async {
    await env.kill(daemon);
    if (schedule != null) _schedule = schedule;
    daemon = await _launch();
    grpc = await ApiHarness.start(env, daemon: daemon);
  }

  /// Registers a public workshop item.
  FakeWorkshopItem item(
    String id, {
    String title = 'Community Framework',
    int size = 2048,
    int updated = 1700000000,
  }) => workshop.add(
    FakeWorkshopItem(id, title: title, fileSize: size, timeUpdated: updated),
  );

  /// An installed, stopped instance.
  Future<Instance> instance({
    String name = 'Friends',
    Map<String, int> ports = const {},
  }) => createInstalled(daemon, name: name, ports: ports);

  Instance current(Instance instance) => daemon.instances.get(instance.id);

  /// SetMods with the revision the instance is at.
  Future<pb.ListModsResponse> setMods(
    Instance instance,
    List<ModSpec> specs, {
    int? expectedRevision,
  }) => mods.setMods(
    pb.SetModsRequest(
      instanceId: instance.id,
      expectedRevision: Int64(expectedRevision ?? current(instance).revision),
      mods: [
        for (final s in specs)
          pb.ModRef(source: s.source, itemId: s.item, role: s.role),
      ],
    ),
  );

  Future<pb.ListModsResponse> list(Instance instance) =>
      mods.listMods(pb.ListModsRequest(instanceId: instance.id));

  /// The listed mod of [item].
  Future<pb.Mod> mod(Instance instance, String item) async =>
      (await list(instance)).mods.singleWhere((m) => m.itemId == item);

  /// Waits until every mod of the instance has its staged name.
  Future<List<String>> names(Instance instance, {int? count}) async {
    var names = <String>[];
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (true) {
      final listed = (await list(instance)).mods;
      names = [for (final m in listed) m.stagedName];
      if ((count == null || listed.length == count) &&
          names.every((n) => n.isNotEmpty)) {
        return names;
      }
      if (DateTime.now().isAfter(deadline)) {
        fail('the staged names were not fixed: $names');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<Operation> _finished(pb.Operation op) =>
      daemon.operations.whenDone(op.id);

  Future<Operation> apply(Instance instance) async => _finished(
    await mods.applyMods(pb.ApplyModsRequest(instanceId: instance.id)),
  );

  Future<Operation> checkUpdates([Instance? instance]) async => _finished(
    await mods.checkModUpdates(
      pb.CheckModUpdatesRequest(instanceId: instance?.id ?? ''),
    ),
  );

  Future<Operation> updateMods(
    Instance instance, [
    List<String> items = const [],
  ]) async => _finished(
    await mods.updateMods(
      pb.UpdateModsRequest(instanceId: instance.id, itemIds: items),
    ),
  );

  /// The steps an operation went through, in order.
  Future<List<String>> steps(Operation op) async => [
    for (final e in await daemon.operations.watch(op.id).toList())
      if (e is StepStartedEvent) e.step,
  ];

  /// `<instance>/server/<name>`.
  String staged(Instance instance, String name) =>
      p.join(instance.directory, 'server', name);

  /// The version directory of [item] in the content store.
  String versionDir(String item, String version) => p.join(
    daemon.dataDirectory.contentPath,
    'steam_workshop',
    dayzWorkshopApp,
    item,
    version,
  );

  /// The launch arguments of the latest launch.
  List<String> get launchArgs => env.process.launches.last.args;

  /// Files and folders of `server/keys/`, sorted.
  List<String> keys(Instance instance) {
    final dir = Directory(p.join(instance.directory, 'server', 'keys'));
    return dir.existsSync()
        ? [for (final e in dir.listSync()) p.basename(e.path)]
        : <String>[];
  }
}

/// Whether [path] is a link or junction (not followed).
bool isLink(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false) ==
    FileSystemEntityType.link;

/// Where the link [path] resolves to, canonical.
String? resolvedTarget(String path) {
  if (!isLink(path)) return null;
  return Directory(path).resolveSymbolicLinksSync();
}

/// Whether [path] is a link that points at the directory [target].
bool linksTo(String path, String target) {
  final resolved = resolvedTarget(path);
  return resolved != null &&
      p.equals(resolved, Directory(target).resolveSymbolicLinksSync());
}

/// Plants a junction at [link] to the directory [target], the way a game
/// server running as another account could.
void plantJunction(String link, String target) {
  Directory(p.dirname(link)).createSync(recursive: true);
  if (Platform.isWindows) {
    final made = Process.runSync('cmd', ['/c', 'mklink', '/J', link, target]);
    expect(made.exitCode, 0, reason: '${made.stdout}${made.stderr}');
  } else {
    Link(link).createSync(target);
  }
}

/// Removes the link [path] itself.
void removeLink(String path) => Link(path).deleteSync();
