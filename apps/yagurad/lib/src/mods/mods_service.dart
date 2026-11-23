import 'dart:async';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:yagura_plugin/yagura_plugin.dart';

import '../content/content.dart';
import '../errors.dart';
import '../files/files.dart';
import '../host/database.dart';
import '../instances/instance_manager.dart';
import '../instances/instance_store.dart';
import '../operations/operations.dart';
import '../plugins/plugin_registry.dart';
import 'mod_check_schedule.dart';
import 'mod_entry.dart';
import 'mod_keys.dart';
import 'mod_names.dart';
import 'mod_stager.dart';
import 'stage_link.dart';

/// The most mods an instance keeps (design D7).
const maxModsPerInstance = 256;

/// One mod of the list a client sets.
class ModRef {
  const ModRef({this.source = '', required this.itemId, this.role = ''});

  final String source;
  final String itemId;
  final String role;
}

/// The mods of an instance as `ListMods` shows them.
class ModsListing {
  const ModsListing({
    required this.mods,
    required this.updateCheck,
    this.checkedAt,
  });

  /// In load order, as copies.
  final List<ModEntry> mods;

  /// `ok` when the last check of the workshop succeeded, `unknown` when it
  /// failed or none ran.
  final String updateCheck;
  final DateTime? checkedAt;
}

/// What the last update check found out about one instance.
class _CheckState {
  const _CheckState(this.ok, this.at, this.error);

  final bool ok;
  final DateTime at;
  final String error;
}

/// The mod pipeline's instance side (design D6, D7, D8, D14): the mod list,
/// staging into the instance's stage directory, key files and the check for
/// newer versions.
class ModsService {
  ModsService({
    required this.manager,
    required this.runner,
    required this.acquirer,
    required this.workshop,
    required this.contentStore,
    required YaguraDatabase database,
    this.schedule = const ModCheckSchedule(),
    this.stageLink = defaultStageLink,
    DateTime Function()? clock,
    Random? random,
    void Function(String message)? log,
  }) : _keys = KeyPlacer(database),
       _clock = clock ?? DateTime.now,
       _random = random ?? Random(),
       _log = log ?? ((_) {});

  final InstanceManager manager;
  final OperationRunner runner;
  final ContentAcquirer acquirer;
  final WorkshopClient workshop;
  final ContentStore contentStore;
  final ModCheckSchedule schedule;
  final StageLinkCreator stageLink;
  final KeyPlacer _keys;
  final DateTime Function() _clock;
  final Random _random;
  final void Function(String message) _log;

  /// The background name fetch of each instance (design D7).
  final _naming = <String, Future<void>>{};
  final _checks = <String, _CheckState>{};
  Timer? _timer;
  var _failures = 0;
  var _closed = false;

  // ---- the list ------------------------------------------------------------

  ModsSpec _spec(InstanceRecord record) {
    final spec = manager.requirePlugin(record).manifest.mods;
    if (spec == null) throw modsNotSupported(record);
    return spec;
  }

  /// The `mods_not_supported` failure for [record].
  static YaguraException modsNotSupported(InstanceRecord record) =>
      YaguraException(
        'mods_not_supported',
        'the plugin ${record.pluginId} of instance "${record.name}" declares '
            'no mod support',
        details: {'instanceId': record.id, 'pluginId': record.pluginId},
      );

  ModsListing list(String instanceId) {
    final record = manager.requireRecord(instanceId);
    final check = _checks[instanceId];
    return ModsListing(
      mods: [for (final mod in record.listedMods) mod.copy()],
      updateCheck: check != null && check.ok ? 'ok' : 'unknown',
      checkedAt: check?.at,
    );
  }

  /// The size of the version a row wants, from the content store when the
  /// title fetch did not report one.
  int sizeOf(ModEntry mod, int appId) {
    if (mod.sizeBytes > 0) return mod.sizeBytes;
    final version = contentStore.find(
      mod.source,
      '$appId',
      mod.itemId,
      mod.desiredVersion.isNotEmpty ? mod.desiredVersion : mod.stagedVersion,
    );
    return version?.sizeBytes ?? 0;
  }

  /// Replaces the mod list of [instanceId] (design D7). Nothing is looked up
  /// before it commits; the names of new workshop mods are fixed by a
  /// background fetch.
  ModsListing setMods(
    String instanceId, {
    required int? expectedRevision,
    required List<ModRef> refs,
  }) {
    final record = manager.requireRecord(instanceId);
    final spec = _spec(record);
    manager.checkRevision(record, expectedRevision);
    if (refs.length > maxModsPerInstance) {
      throw YaguraException(
        'too_many_mods',
        'an instance keeps at most $maxModsPerInstance mods, not '
            '${refs.length}',
        details: {'limit': maxModsPerInstance, 'count': refs.length},
      );
    }
    final existing = {for (final mod in record.mods) mod.key: mod};
    final next = <ModEntry>[];
    final seen = <String>{};
    for (final (i, ref) in refs.indexed) {
      final at = 'mods[$i]';
      final source = ref.source.isEmpty ? spec.source.wireName : ref.source;
      if (source != spec.source.wireName) {
        throw YaguraException(
          'mod_invalid',
          '$at: the plugin takes mods from ${spec.source.wireName}, not '
              '$source',
          details: {'index': i, 'source': source},
        );
      }
      _checkItemId(spec, ref.itemId, at);
      final role = _roleOf(spec, ref.role, at);
      final key = '$source|${ref.itemId}';
      if (!seen.add(key)) {
        throw YaguraException(
          'mod_invalid',
          '$at: the mod ${ref.itemId} is listed twice',
          details: {'index': i, 'item': ref.itemId},
        );
      }
      final kept = existing[key];
      if (kept == null) {
        next.add(
          ModEntry(
            source: source,
            itemId: ref.itemId,
            role: role,
            stagedName: spec.source == ModSource.serverManaged
                ? ref.itemId
                : '',
          ),
        );
      } else {
        final entry = kept.copy()..role = role;
        if (entry.isRemoved) {
          entry.status =
              entry.stagedVersion.isNotEmpty &&
                  entry.stagedVersion == entry.desiredVersion
              ? ModEntry.staged
              : ModEntry.pending;
        }
        next.add(entry);
      }
    }
    // A mod taken out while its entry is in the stage directory stays as a
    // removed row, so the next apply finds the entry it made.
    for (final mod in record.mods) {
      if (seen.contains(mod.key)) continue;
      if (mod.stageKind.isEmpty || mod.stagedName.isEmpty) continue;
      next.add(
        mod.copy()
          ..status = ModEntry.removed
          ..updateAvailable = false,
      );
    }
    manager.commitMods(record, next);
    _nameInBackground(record);
    return list(instanceId);
  }

  void _checkItemId(ModsSpec spec, String itemId, String at) {
    final ok = spec.source == ModSource.steamWorkshop
        ? RegExp(r'^[0-9]{1,20}$').hasMatch(itemId)
        : RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(itemId);
    if (!ok) {
      throw YaguraException(
        'mod_invalid',
        '$at: "$itemId" is not a ${spec.source == ModSource.steamWorkshop ? 'workshop item id (digits only)' : 'mod id (letters, digits, . _ -)'}',
        details: {'item': itemId},
      );
    }
  }

  String _roleOf(ModsSpec spec, String role, String at) {
    if (role.isEmpty && spec.roles.length == 1) return spec.roles.single;
    if (spec.roles.contains(role)) return role;
    throw YaguraException(
      'mod_role_invalid',
      '$at: the role "$role" is not one of the plugin\'s roles: '
          '${spec.roles.join(', ')}',
      details: {'role': role, 'roles': spec.roles.join(',')},
    );
  }

  // ---- names ---------------------------------------------------------------

  /// Starts the fetch that fixes the names of [record]'s unnamed mods, after
  /// any fetch still running for it.
  void _nameInBackground(InstanceRecord record) {
    final spec = manager.registry.find(record.pluginId)?.manifest.mods;
    if (spec == null || spec.source != ModSource.steamWorkshop) return;
    if (record.listedMods.every((m) => m.stagedName.isNotEmpty)) return;
    final previous = _naming[record.id] ?? Future<void>.value();
    late final Future<void> chain;
    chain = previous.then((_) => _fixNames(record, spec)).whenComplete(() {
      if (identical(_naming[record.id], chain)) _naming.remove(record.id);
    });
    _naming[record.id] = chain;
  }

  Future<void> _fixNames(InstanceRecord record, ModsSpec spec) async {
    final unnamed = [
      for (final mod in record.listedMods)
        if (mod.stagedName.isEmpty) mod.itemId,
    ];
    if (unnamed.isEmpty) return;
    Map<String, WorkshopItemDetails>? details;
    try {
      details = await workshop.details(unnamed);
    } on Object catch (e) {
      _log('could not read the titles of ${record.id}\'s mods: $e');
    }
    if (_closed) return;
    final titles = {
      for (final id in unnamed)
        if (details?[id] case final d? when d.available) id: d.title,
    };
    final sizes = {
      for (final id in unnamed)
        if (details?[id] case final d? when d.available) id: d.sizeBytes,
    };
    _nameUnnamed(record, spec, titles, sizes);
  }

  /// Fixes the name of every unnamed listed mod once: from its title in
  /// [titles], else from its item id.
  void _nameUnnamed(
    InstanceRecord record,
    ModsSpec spec,
    Map<String, String> titles,
    Map<String, int> sizes,
  ) {
    if (manager.find(record.id) == null) return;
    final taken = <String>{
      for (final mod in record.mods)
        if (mod.stagedName.isNotEmpty) mod.stagedName.toLowerCase(),
      ...ModStager(
        fs: InstanceFs(record.directory),
        spec: spec,
        instanceId: record.id,
        operationId: '',
        stageLink: stageLink,
      ).presentNames(),
    };
    var changed = false;
    for (final mod in record.listedMods) {
      if (sizes[mod.itemId] case final size?) mod.sizeBytes = size;
      final title = titles[mod.itemId];
      if (title != null && title.isNotEmpty) mod.title = title;
      if (mod.stagedName.isNotEmpty) continue;
      final name = uniqueModName(
        renderModName(spec.linkName, title, mod.itemId),
        taken,
      );
      taken.add(name.toLowerCase());
      mod.stagedName = name;
      changed = true;
    }
    if (changed) manager.saveChanges(record);
  }

  // ---- staging -------------------------------------------------------------

  /// The mods an `UpdateMods` of [items] refreshes: those named, else every
  /// listed mod with an update available.
  Set<String> updateTargets(InstanceRecord record, List<String> items) {
    final listed = record.listedMods;
    if (items.isEmpty) {
      return {
        for (final mod in listed)
          if (mod.updateAvailable) mod.itemId,
      };
    }
    for (final item in items) {
      if (!listed.any((m) => m.itemId == item)) {
        throw YaguraException(
          'mod_invalid',
          'the mod $item is not in the list of instance "${record.name}"',
          details: {'item': item},
        );
      }
    }
    return {...items};
  }

  /// Brings the mods of [record] to what the list wants (design D7): acquires
  /// the versions it lacks and those in [refresh] at their newest, then, when
  /// [place], links or copies them into the stage directory, removes the
  /// entries of removed mods and places the key files. The caller has checked
  /// that the instance is stopped when [place] is set.
  Future<void> stage(
    OperationContext ctx,
    InstanceRecord record,
    LoadedPlugin plugin, {
    Set<String> refresh = const {},
    bool refreshAll = false,
    bool place = true,
  }) async {
    final spec = plugin.manifest.mods!;
    await (_naming[record.id] ?? Future<void>.value());
    ctx.cancel.throwIfCancelled();
    final listed = record.listedMods;
    if (spec.source == ModSource.serverManaged) {
      for (final mod in listed) {
        mod.status = ModEntry.staged;
        mod.lastError = '';
        mod.warnings = [];
      }
      record.mods = listed;
      manager.saveChanges(record);
      return;
    }

    final appId = spec.workshopAppId!;
    final wanted = [
      for (final mod in listed)
        if (refreshAll ||
            refresh.contains(mod.itemId) ||
            mod.desiredVersion.isEmpty ||
            contentStore.find(
                  mod.source,
                  '$appId',
                  mod.itemId,
                  mod.desiredVersion,
                ) ==
                null)
          mod,
    ];
    final titles = <String, String>{};
    final sizes = <String, int>{};
    if (wanted.isNotEmpty) {
      await _acquire(ctx, record, appId, wanted, titles, sizes);
    }
    _nameUnnamed(record, spec, titles, sizes);
    if (!place) {
      manager.saveChanges(record);
      return;
    }
    ctx.cancel.throwIfCancelled();
    try {
      _place(ctx, record, spec);
    } finally {
      manager.saveChanges(record);
    }
  }

  Future<void> _acquire(
    OperationContext ctx,
    InstanceRecord record,
    int appId,
    List<ModEntry> wanted,
    Map<String, String> titles,
    Map<String, int> sizes,
  ) async {
    final account = record.steamAccountId.isEmpty
        ? null
        : manager.accounts.useFor(record.steamAccountId);
    for (final mod in wanted) {
      if (mod.status != ModEntry.staged) mod.status = ModEntry.downloading;
    }
    manager.saveChanges(record);
    final AcquireResult result;
    try {
      result = await acquirer.acquire(
        AcquireRequest(
          workshopAppId: '$appId',
          items: [for (final mod in wanted) mod.itemId],
          account: account,
        ),
        ctx,
      );
    } on Object {
      for (final mod in wanted) {
        if (mod.status == ModEntry.downloading) mod.status = ModEntry.pending;
      }
      manager.saveChanges(record);
      rethrow;
    }
    for (final mod in wanted) {
      final item = result[mod.itemId];
      if (item.ok) {
        mod.desiredVersion = item.version;
        mod.remoteUpdated = int.tryParse(item.version) ?? mod.remoteUpdated;
        mod.updateAvailable = false;
        mod.sizeBytes = item.sizeBytes;
        if (item.title.isNotEmpty) {
          mod.title = item.title;
          titles[mod.itemId] = item.title;
        }
        sizes[mod.itemId] = item.sizeBytes;
        mod.lastError = '';
        if (mod.status == ModEntry.downloading ||
            mod.status == ModEntry.failed ||
            mod.status == ModEntry.unavailable) {
          mod.status = mod.stagedVersion == item.version
              ? ModEntry.staged
              : ModEntry.pending;
        }
      } else {
        final error = item.error!;
        mod.status = error.reason == 'workshop_item_unavailable'
            ? ModEntry.unavailable
            : ModEntry.failed;
        mod.lastError = '${error.reason}: ${error.message}';
      }
    }
    manager.saveChanges(record);
    result.throwIfFailed();
  }

  /// Makes the entries (design D7, steps 3 to 5, without the hook).
  void _place(OperationContext ctx, InstanceRecord record, ModsSpec spec) {
    final fs = InstanceFs(record.directory);
    final stager = ModStager(
      fs: fs,
      spec: spec,
      instanceId: record.id,
      operationId: ctx.operationId,
      stageLink: stageLink,
    );
    fs.createDirectory(spec.stageDir);
    final appId = spec.workshopAppId!;
    final failures = <YaguraException>[];

    for (final mod in record.listedMods) {
      final target = contentStore.pathOf(
        mod.source,
        '$appId',
        mod.itemId,
        mod.desiredVersion,
      );
      try {
        final entry = stager.entryNamed(mod.stagedName);
        if (entry != null) {
          if (!stager.isRecorded(mod, entry)) throw stager.conflict(mod);
          if (stager.isCurrent(mod, entry, target)) {
            mod.stagedVersion = mod.desiredVersion;
            mod.status = ModEntry.staged;
            mod.lastError = '';
            continue;
          }
          stager.remove(mod);
        }
        mod.stageKind = stager.create(mod, target);
        mod.stagedVersion = mod.desiredVersion;
        mod.status = ModEntry.staged;
        mod.lastError = '';
      } on YaguraException catch (e) {
        mod.status = ModEntry.failed;
        mod.lastError = '${e.reason}: ${e.message}';
        failures.add(e);
      }
    }

    // The entries of mods no longer listed go by the same rule; one that is
    // not recorded is left.
    final kept = <ModEntry>[];
    for (final mod in record.mods) {
      if (!mod.isRemoved) {
        kept.add(mod);
        continue;
      }
      try {
        final entry = stager.entryNamed(mod.stagedName);
        if (entry != null && stager.isRecorded(mod, entry)) {
          stager.remove(mod);
        }
      } on YaguraException catch (e) {
        _log('could not remove ${stager.pathOf(mod)}: ${e.message}');
        kept.add(mod);
      }
    }
    record.mods = kept;

    if (failures.isNotEmpty) throw failures.first;

    final warnings = _keys.place(
      fs: fs,
      instanceId: record.id,
      spec: spec,
      sources: [
        for (final mod in record.listedMods)
          if (mod.status == ModEntry.staged)
            KeySource(
              mod,
              contentStore.pathOf(
                mod.source,
                '$appId',
                mod.itemId,
                mod.stagedVersion,
              ),
            ),
      ],
    );
    for (final mod in record.listedMods) {
      mod.warnings = warnings[mod.key] ?? [];
    }
  }

  // ---- the update check ----------------------------------------------------

  /// Reads the workshop for the newest version of every workshop mod of
  /// [instanceId], or of every instance when it is empty (design D14). A
  /// failed read keeps the flags it had and ends the operation `succeeded`
  /// with the reason `update_check_unknown`.
  Future<void> checkUpdates(
    OperationContext ctx, {
    String instanceId = '',
  }) async {
    final records = <InstanceRecord>[];
    if (instanceId.isEmpty) {
      for (final record in manager.records) {
        final spec = manager.registry.find(record.pluginId)?.manifest.mods;
        if (spec?.source == ModSource.steamWorkshop) records.add(record);
      }
    } else {
      final record = manager.recordForOperation(instanceId);
      if (_spec(record).source == ModSource.steamWorkshop) records.add(record);
    }
    final ids = <String>{
      for (final record in records)
        for (final mod in record.listedMods) mod.itemId,
    };
    final Map<String, WorkshopItemDetails> details;
    try {
      details = ids.isEmpty
          ? const {}
          : await ctx.step('check', () => workshop.details(ids));
    } on YaguraException catch (e) {
      if (e.reason != 'workshop_metadata_failed') rethrow;
      final now = _clock();
      for (final record in records) {
        _checks[record.id] = _CheckState(false, now, e.message);
      }
      ctx.result(reason: 'update_check_unknown', message: e.message);
      return;
    }
    ctx.cancel.throwIfCancelled();
    final now = _clock();
    for (final record in records) {
      var changed = false;
      for (final mod in record.listedMods) {
        final d = details[mod.itemId];
        if (d == null) continue;
        if (d.title.isNotEmpty && mod.title != d.title) mod.title = d.title;
        if (d.sizeBytes > 0) mod.sizeBytes = d.sizeBytes;
        if (!d.available) continue;
        final available =
            mod.desiredVersion.isNotEmpty &&
            _newer(d.version, mod.desiredVersion);
        if (mod.remoteUpdated != d.timeUpdated ||
            mod.updateAvailable != available) {
          mod
            ..remoteUpdated = d.timeUpdated
            ..updateAvailable = available;
          changed = true;
        }
      }
      _checks[record.id] = _CheckState(true, now, '');
      if (changed) manager.saveChanges(record);
    }
  }

  static bool _newer(String remote, String desired) {
    final a = int.tryParse(remote);
    final b = int.tryParse(desired);
    return a != null && b != null ? a > b : remote != desired;
  }

  // ---- the timer -----------------------------------------------------------

  /// Starts the update check timer (design D14) and the name fetches a
  /// previous run did not finish.
  void start() {
    for (final record in manager.records) {
      _nameInBackground(record);
    }
    if (!schedule.enabled || _timer != null || _closed) return;
    _timer = Timer(schedule.first, _tick);
  }

  Future<void> _tick() async {
    if (_closed) return;
    var failed = false;
    try {
      final operation = manager.checkModUpdates('');
      final done = await runner.whenDone(operation.id);
      failed =
          done.status != OperationStatus.succeeded ||
          done.resultReason == 'update_check_unknown';
    } on Object catch (e) {
      _log('the scheduled mod update check failed: $e');
      failed = true;
    }
    if (_closed) return;
    final Duration gap;
    if (failed) {
      _failures++;
      gap = schedule.backoff(_failures);
    } else {
      _failures = 0;
      gap = schedule.next(_random);
    }
    _timer = Timer(gap, _tick);
  }

  void close() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
  }
}

/// The version directory of a mod's staged version, for the recorded-junction
/// map (design D7).
String stagedVersionPath(String contentPath, ModsSpec spec, ModEntry mod) =>
    p.join(
      contentPath,
      mod.source,
      '${spec.workshopAppId}',
      mod.itemId,
      mod.stagedVersion,
    );
