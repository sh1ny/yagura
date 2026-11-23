import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/files/files.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/content_support.dart';
import '../support/daemon_support.dart';
import '../support/mods_support.dart';

const oldVersion = '1700000000';

/// A manifest whose mods are copied when a link cannot be made.
String withoutCopyFallback() => moddedValheimManifest(
  mods: workshopModsSection.replaceFirst(
    'copy_fallback: true',
    'copy_fallback: false',
  ),
);

void refuseLinks(InstanceFs fs, String path, String target) =>
    throw const FileSystemException(
      'the volume does not support junctions',
      r'\\server\share',
    );

void main() {
  test('dayz_mod_linked', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'Community Framework');
    final instance = await rig.instance();
    await rig.setMods(instance, [ModSpec(cfMod)]);

    final done = await runStart(rig.daemon, instance.id);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    // `<instance>/server/@Community-Framework` is a directory link to the
    // pinned version in the content store.
    final link = rig.staged(instance, '@Community-Framework');
    expect(isLink(link), isTrue);
    expect(linksTo(link, rig.versionDir(cfMod, oldVersion)), isTrue);
    expect(
      File(p.join(link, 'meta.cpp')).readAsStringSync(),
      contains('publishedid = $cfMod'),
    );
    expect(rig.launchArgs, contains('-mod=@Community-Framework'));
    final mod = await rig.mod(instance, cfMod);
    expect(mod.stagedName, '@Community-Framework');
    expect(mod.name, 'Community Framework');
    expect(mod.status, 'staged');
    expect(mod.stagedVersion, oldVersion);
    expect(mod.desiredVersion, oldVersion);
  });

  test('title_unavailable_when_added', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'Community Framework');
    final instance = await rig.instance();
    // The metadata request made when the mod is added fails.
    rig.workshop.failWith.add(500);

    await rig.setMods(instance, [ModSpec(cfMod)]);

    expect(await rig.names(instance), ['@$cfMod']);

    // The title becomes known when the mod is downloaded; the name stays.
    final done = await rig.apply(instance);
    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    final mod = await rig.mod(instance, cfMod);
    expect(mod.stagedName, '@$cfMod');
    expect(mod.name, 'Community Framework');
    expect(isLink(rig.staged(instance, '@$cfMod')), isTrue);
    expect(
      Directory(p.join(instance.directory, 'server'))
          .listSync()
          .map((e) => p.basename(e.path)),
      isNot(contains('@Community-Framework')),
    );
  });

  test('admin_folder_with_the_staged_name', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'Community Framework');
    final instance = await rig.instance();
    await rig.setMods(instance, [ModSpec(cfMod)]);
    expect(await rig.names(instance), ['@Community-Framework']);
    // The admin made a folder with that name since.
    final folder = Directory(rig.staged(instance, '@Community-Framework'))
      ..createSync(recursive: true);
    File(p.join(folder.path, 'admin.txt')).writeAsStringSync('mine');

    final done = await rig.apply(instance);

    expect(done.status, OperationStatus.failed);
    expect(done.resultReason, 'stage_name_conflict');
    expect(done.resultMessage, contains('@Community-Framework'));
    expect(isLink(folder.path), isFalse);
    expect(Directory(folder.path).listSync().map((e) => p.basename(e.path)), [
      'admin.txt',
    ]);
    expect(File(p.join(folder.path, 'admin.txt')).readAsStringSync(), 'mine');
    final mod = await rig.mod(instance, cfMod);
    expect(mod.status, 'failed');
    expect(mod.lastError, contains('stage_name_conflict'));
  });

  test('mod_renamed_on_the_workshop', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'Community Framework');
    final instance = await rig.instance();
    await rig.setMods(instance, [ModSpec(cfMod)]);
    await rig.apply(instance);

    // The title changes with a new version.
    rig.workshop.items[cfMod]!
      ..title = 'CF Renamed'
      ..timeUpdated = 1700500000;
    await rig.checkUpdates(instance);
    final updated = await rig.updateMods(instance);
    expect(updated.status, OperationStatus.succeeded);
    final done = await runStart(rig.daemon, instance.id);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    // The staged name and the launch arguments are as they were.
    final mod = await rig.mod(instance, cfMod);
    expect(mod.stagedName, '@Community-Framework');
    expect(rig.launchArgs, contains('-mod=@Community-Framework'));
    expect(
      linksTo(
        rig.staged(instance, '@Community-Framework'),
        rig.versionDir(cfMod, '1700500000'),
      ),
      isTrue,
    );
    expect(
      File(rig.staged(instance, '@CF-Renamed')).existsSync() ||
          Directory(rig.staged(instance, '@CF-Renamed')).existsSync(),
      isFalse,
    );
  });

  test('names_are_unique_and_safe', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'Same Name');
    rig.item(vppMod, title: 'Same Name');
    rig.item(thirdMod, title: 'Odd / "Mod": *');
    final instance = await rig.instance();
    // An entry of the stage directory already has the first free name.
    Directory(rig.staged(instance, '@Same-Name')).createSync(recursive: true);

    await rig.setMods(instance, [
      ModSpec(cfMod),
      ModSpec(vppMod),
      ModSpec(thirdMod),
    ]);

    final names = await rig.names(instance);
    expect(names.take(2), ['@Same-Name-2', '@Same-Name-3']);
    expect(names.last, matches(RegExp(r'^@[A-Za-z0-9._-]+$')));
  });

  test('link_not_permitted', () async {
    final rig = await ModsRig.start(
      manifest: withoutCopyFallback(),
      stageLink: refuseLinks,
    );
    rig.item(cfMod, title: 'Community Framework');
    final instance = await rig.instance();
    await rig.setMods(instance, [ModSpec(cfMod)]);

    final done = await rig.apply(instance);

    expect(done.status, OperationStatus.failed);
    expect(done.resultReason, 'stage_link_failed');
    expect(done.resultMessage, contains('does not support junctions'));
    // No partial copy: nothing at the name, no staging directory.
    expect(
      FileSystemEntity.typeSync(
        rig.staged(instance, '@Community-Framework'),
        followLinks: false,
      ),
      FileSystemEntityType.notFound,
    );
    final scratch = Directory(p.join(instance.directory, '.yagura'));
    expect(
      scratch.existsSync()
          ? scratch
                .listSync()
                .map((e) => p.basename(e.path))
                .where((n) => n.startsWith('stage-'))
          : const <String>[],
      isEmpty,
    );
  });

  test('link_failure_falls_back_to_a_copy', () async {
    final rig = await ModsRig.start(stageLink: refuseLinks);
    rig.item(cfMod, title: 'Community Framework');
    final instance = await rig.instance();
    await rig.setMods(instance, [ModSpec(cfMod)]);

    final done = await rig.apply(instance);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    // A real directory with the content and the marker of Yagura's copy.
    final copy = rig.staged(instance, '@Community-Framework');
    expect(isLink(copy), isFalse);
    expect(Directory(copy).existsSync(), isTrue);
    expect(File(p.join(copy, 'meta.cpp')).existsSync(), isTrue);
    final marker = jsonDecode(
      File(p.join(copy, '.yagura-staged')).readAsStringSync(),
    ) as Map<String, Object?>;
    expect(marker, containsPair('instanceId', instance.id));
    expect(marker, containsPair('itemId', cfMod));

    // A recorded copy is replaced by the next version's, an unmarked one is
    // an admin's folder.
    rig.workshop.items[cfMod]!.timeUpdated = 1700500000;
    await rig.checkUpdates(instance);
    expect((await rig.updateMods(instance)).status, OperationStatus.succeeded);
    expect(File(p.join(copy, 'build.txt')).readAsStringSync(), '2');
    File(p.join(copy, '.yagura-staged')).deleteSync();
    rig.workshop.items[cfMod]!.timeUpdated = 1700900000;
    await rig.checkUpdates(instance);
    final conflict = await rig.updateMods(instance);
    expect(conflict.resultReason, 'stage_name_conflict');
    expect(File(p.join(copy, 'build.txt')).readAsStringSync(), '2');
  });

  test('staged_link_replaced_by_the_server', () async {
    final rig = await ModsRig.start(
      // After the stop the hook reads through the link and says what happened.
      hooks: r'''
exports.onPostStop = function () {
  let code = 'read';
  try { yagura.fs.readText('server/@CF/meta.cpp'); } catch (e) { code = e.code; }
  return {files: [{path: 'probe.json', format: 'json', patch: {code: code}}]};
};
''',
    );
    rig.item(cfMod, title: 'CF');
    final instance = await rig.instance();
    await rig.setMods(instance, [ModSpec(cfMod)]);
    await runStart(rig.daemon, instance.id);
    final link = rig.staged(instance, '@CF');
    expect(linksTo(link, rig.versionDir(cfMod, oldVersion)), isTrue);
    File(p.join(instance.directory, 'probe.json')).writeAsStringSync('{}');

    // The server's account replaces the link with a junction elsewhere.
    final other = Directory(p.join(rig.env.root.path, 'elsewhere'))
      ..createSync();
    File(p.join(other.path, 'meta.cpp')).writeAsStringSync('not the mod');
    removeLink(link);
    plantJunction(link, other.path);
    await runStop(rig.daemon, instance.id);

    // Daemon file operations through it fail with sandbox_violation.
    final probe = jsonDecode(
      File(p.join(instance.directory, 'probe.json')).readAsStringSync(),
    ) as Map<String, Object?>;
    expect(probe['code'], 'sandbox_violation');
    expect(
      File(p.join(other.path, 'meta.cpp')).readAsStringSync(),
      'not the mod',
    );

    // The next staging removes that link without following it and makes the
    // recorded one again.
    final done = await runStart(rig.daemon, instance.id);
    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(linksTo(link, rig.versionDir(cfMod, oldVersion)), isTrue);
    expect(
      File(p.join(other.path, 'meta.cpp')).readAsStringSync(),
      'not the mod',
    );
    await runStop(rig.daemon, instance.id);
    expect(
      (jsonDecode(
        File(p.join(instance.directory, 'probe.json')).readAsStringSync(),
      ) as Map<String, Object?>)['code'],
      'read',
    );
  });
}
