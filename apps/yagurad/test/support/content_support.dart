import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/content/content.dart';
import 'package:yagurad/src/host/data_directory.dart';
import 'package:yagurad/src/host/database.dart';
import 'package:yagurad/src/host/migrations.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/platform/disk_space.dart';
import 'package:yagurad/src/steam/steam.dart';

import '../fixtures/fake_workshop_api.dart';
import 'daemon_support.dart';
import 'steam_support.dart';

/// The workshop app of DayZ, and a mod of it.
const dayzWorkshopApp = '221100';
const cfMod = '1559212036';

/// The pieces of the content pipeline, wired to the fake SteamCMD and the
/// fake Steam Web API inside a [TestEnv]'s data directory.
class ContentRig {
  ContentRig._(
    this.env,
    this.steam,
    this.api,
    this.data,
    this.db,
    this.runner,
    this.workshop,
    this.store,
    this.acquirer,
    this.clock,
  );

  final TestEnv env;
  final SteamHarness steam;
  final FakeWorkshopApi api;
  final DataDirectory data;
  final YaguraDatabase db;
  final OperationRunner runner;
  final WorkshopClient workshop;
  final ContentStore store;
  final ContentAcquirer acquirer;

  /// The store's clock; move [now] to age versions.
  final MutableClock clock;

  /// Wires the pipeline. [steamFactory] replaces the SteamCMD service (a
  /// fake that raises prompts, say); the harness still owns the data
  /// directory and the fake Web API.
  static Future<ContentRig> start({
    Map<String, String> fakeEnvironment = const {},
    bool realOutput = true,
    int heavySlots = 4,
    Duration minInterval = const Duration(milliseconds: 20),
    Duration requestTimeout = const Duration(seconds: 15),
    SteamService Function(String steamcmdRoot)? steamFactory,
    int freeBytes = 1 << 40,
  }) async {
    final env = TestEnv();
    final steam = SteamHarness(
      env,
      realOutput: realOutput,
      freeBytes: freeBytes,
      fakeEnvironment: {'FAKE_STEAMCMD_DELAY_MS': '20', ...fakeEnvironment},
    );
    final api = await FakeWorkshopApi.start();
    addTearDown(api.close);
    final data = DataDirectory.prepare(env.data);
    final db = YaguraDatabase.open(
      data.databasePath,
      migrations: allMigrations,
    );
    // The tests name instances that were never created.
    db.sqlite.execute('PRAGMA foreign_keys = OFF');
    final runner = OperationRunner(database: db, heavySlots: heavySlots);
    final workshop = WorkshopClient(
      endpoint: api.endpoint,
      minInterval: minInterval,
      requestTimeout: requestTimeout,
    );
    final clock = MutableClock(DateTime.utc(2026, 10, 20, 12));
    final store = ContentStore(
      database: db,
      contentPath: data.contentPath,
      clock: clock.call,
    );
    final acquirer = ContentAcquirer(
      runner: runner,
      store: store,
      workshop: workshop,
      steam: steamFactory?.call(data.steamcmdPath) ?? steam.service,
      steamcmdRoot: data.steamcmdPath,
      diskSpace: (path) async =>
          DiskSpace(volume: r'V:\', freeBytes: steam.free),
    );
    final rig = ContentRig._(
      env,
      steam,
      api,
      data,
      db,
      runner,
      workshop,
      store,
      acquirer,
      clock,
    );
    addTearDown(() async {
      store.close();
      workshop.close();
      await runner.close();
      db.close();
    });
    return rig;
  }

  /// The results the acquiring operations got, by operation id.
  final results = <String, AcquireResult>{};

  /// Queues an operation on [instanceId] that acquires [items] and keeps the
  /// result. With [requireAll] it fails like a mod pipeline would when an item
  /// is unavailable.
  Operation acquire(
    String instanceId,
    List<String> items, {
    SteamAccountUse? account,
    bool requireAll = false,
    void Function(OperationContext ctx)? onStart,
  }) {
    return runner.enqueue(
      instanceId: instanceId,
      kind: OperationKind.update,
      body: (ctx) async {
        onStart?.call(ctx);
        final result = await acquirer.acquire(
          AcquireRequest(
            workshopAppId: dayzWorkshopApp,
            items: items,
            account: account,
          ),
          ctx,
        );
        results[ctx.operationId] = result;
        if (requireAll) result.throwIfFailed();
      },
    );
  }

  Future<Operation> finished(Operation op) => runner.whenDone(op.id);

  /// Registers a public workshop item in the fake Web API.
  FakeWorkshopItem item(
    String id, {
    String title = 'Community Framework',
    int size = 2048,
    int updated = 1700000000,
  }) => api.add(
    FakeWorkshopItem(id, title: title, fileSize: size, timeUpdated: updated),
  );

  /// The workshop runs the fake SteamCMD recorded.
  List<Map<String, Object?>> workshopRuns() => [
    for (final run in steam.runs())
      if ((run['args']! as List).contains('+workshop_download_item')) run,
  ];

  /// The version directories below `content/steam_workshop/<app>/<item>/`.
  List<String> publishedVersions(String item, [String app = dayzWorkshopApp]) {
    final dir = Directory(
      p.join(data.contentPath, ContentStore.workshopSource, app, item),
    );
    if (!dir.existsSync()) return const [];
    return [
      for (final e in dir.listSync())
        if (e is Directory) p.basename(e.path),
    ]..sort();
  }

  /// Everything under `content/.staging`.
  List<String> stagingLeftovers() {
    final dir = Directory(data.contentStagingPath);
    return dir.existsSync()
        ? [for (final e in dir.listSync()) p.basename(e.path)]
        : const [];
  }

  /// Records that [instanceId] uses [version] of [item] (the mod rows of
  /// task group 7 do this for real).
  void reference(
    String instanceId,
    String item, {
    String staged = '',
    String desired = '',
    int position = 0,
  }) {
    db.sqlite.execute(
      'INSERT OR REPLACE INTO instance_mods (instance_id, position, source, '
      'item_id, staged_version, desired_version) VALUES (?, ?, ?, ?, ?, ?)',
      [
        instanceId,
        position,
        ContentStore.workshopSource,
        item,
        staged,
        desired,
      ],
    );
  }

  void unreference(String instanceId) => db.sqlite.execute(
    'DELETE FROM instance_mods WHERE instance_id = ?',
    [instanceId],
  );

  /// `content_versions` rows, as `item/version`.
  List<String> rows() => [
    for (final row in db.sqlite.select(
      'SELECT item, version FROM content_versions ORDER BY item, version',
    ))
      '${row['item']}/${row['version']}',
  ];

  /// A SteamCMD installation of an account, marked ready.
  String installAccount(String id) {
    Directory(p.join(steam.root, id)).createSync(recursive: true);
    steam.state.markReady(id);
    return id;
  }
}

/// A clock a test moves.
class MutableClock {
  MutableClock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);
}

/// A Steam service for tests of the pipeline's own behaviour: the workshop
/// run is [onRun], everything else is refused.
class ScriptedWorkshopSteam implements SteamService {
  ScriptedWorkshopSteam(this.root, this.onRun);

  /// `<data>/steamcmd`.
  final String root;
  final Future<List<SteamWorkshopItemResult>> Function(
    SteamWorkshopRequest request,
    SteamRunReporter reporter,
    CancelToken cancel,
  )
  onRun;
  final runs = <SteamWorkshopRequest>[];

  /// Writes the content SteamCMD would have downloaded for [item].
  void writeItem(String installation, int app, String item) {
    final dir = Directory(
      p.join(
        root,
        installation,
        'steamapps',
        'workshop',
        'content',
        '$app',
        item,
      ),
    )..createSync(recursive: true);
    File(p.join(dir.path, 'mod.txt')).writeAsStringSync('mod $item');
  }

  @override
  Future<List<SteamWorkshopItemResult>> downloadWorkshopItems(
    SteamWorkshopRequest request,
    SteamRunReporter reporter,
    CancelToken cancel,
  ) {
    runs.add(request);
    return onRun(request, reporter, cancel);
  }

  @override
  Future<void> installApp(
    SteamAppRequest request,
    SteamRunReporter reporter,
    CancelToken cancel,
  ) => throw UnimplementedError();

  @override
  Future<void> login(
    SteamLoginRequest request,
    SteamRunReporter reporter,
    CancelToken cancel,
  ) => throw UnimplementedError();

  @override
  Future<void> removeInstallation(String account) async {}

  @override
  Future<void> sweepStrays() async {}

  @override
  Future<void> close() async {}
}
