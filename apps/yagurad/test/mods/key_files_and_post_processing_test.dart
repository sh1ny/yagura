import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';

import '../support/content_support.dart';
import '../support/mods_support.dart';

/// A mod whose only content is the key files [keys] (name to content).
Map<String, List<int>> modWithKeys(Map<String, String> keys) => {
  'addons/mod.pbo': List.filled(8, 1),
  for (final MapEntry(:key, :value) in keys.entries)
    'keys/$key': utf8.encode(value),
};

File keyFile(Instance instance, String name) =>
    File(p.join(instance.directory, 'server', 'keys', name));

void main() {
  test('bikeys_synced', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'CF');
    rig.item(vppMod, title: 'VPP');
    final instance = await rig.instance();
    // The admin has a key of their own.
    keyFile(instance, 'admin.bikey')
      ..createSync(recursive: true)
      ..writeAsStringSync('the admin key');
    await rig.setMods(instance, [ModSpec(cfMod), ModSpec(vppMod)]);

    final done = await rig.apply(instance);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    // Each mod's key is in `server/keys/`, next to the admin's, unchanged.
    expect(rig.keys(instance)..sort(), [
      '$cfMod.bikey',
      '$vppMod.bikey',
      'admin.bikey',
    ]);
    expect(
      keyFile(instance, 'admin.bikey').readAsStringSync(),
      'the admin key',
    );
    expect(
      keyFile(instance, '$cfMod.bikey').readAsBytesSync(),
      List.filled(16, 3),
    );
    // The key files are copies in the instance, not links.
    expect(isLink(keyFile(instance, '$cfMod.bikey').path), isFalse);
  });

  test('shared_key_kept', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'CF');
    rig.item(vppMod, title: 'VPP');
    // Both ship the same CF.bikey.
    rig.steam.files[cfMod] = modWithKeys({'CF.bikey': 'cf key'});
    rig.steam.files[vppMod] = modWithKeys({'CF.bikey': 'cf key'});
    final instance = await rig.instance();
    await rig.setMods(instance, [ModSpec(cfMod), ModSpec(vppMod)]);
    await rig.apply(instance);
    expect(rig.keys(instance), ['CF.bikey']);

    // Mod X goes; Y still provides the key.
    await rig.setMods(instance, [ModSpec(vppMod)]);
    final done = await rig.apply(instance);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(keyFile(instance, 'CF.bikey').readAsStringSync(), 'cf key');
    // With Y gone too the key goes.
    await rig.setMods(instance, []);
    await rig.apply(instance);
    expect(keyFile(instance, 'CF.bikey').existsSync(), isFalse);
  });

  test('admin_s_own_key_with_the_same_name', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'CF');
    rig.steam.files[cfMod] = modWithKeys({'CF.bikey': 'the mod key'});
    final instance = await rig.instance();
    keyFile(instance, 'CF.bikey')
      ..createSync(recursive: true)
      ..writeAsStringSync('the admin key');
    await rig.setMods(instance, [ModSpec(cfMod)]);

    final done = await rig.apply(instance);

    // The admin's key is not overwritten, and the mod shows the conflict.
    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(keyFile(instance, 'CF.bikey').readAsStringSync(), 'the admin key');
    final mod = await rig.mod(instance, cfMod);
    expect(mod.warnings, contains('key_conflict:CF.bikey'));
    expect(mod.status, 'staged');
    // Removing the mod does not remove a key the daemon did not place.
    await rig.setMods(instance, []);
    await rig.apply(instance);
    expect(keyFile(instance, 'CF.bikey').readAsStringSync(), 'the admin key');
  });

  test('mod_removed_takes_its_key', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'CF');
    rig.item(vppMod, title: 'VPP');
    rig.steam.files[cfMod] = modWithKeys({'CF.bikey': 'cf key'});
    rig.steam.files[vppMod] = modWithKeys({'VPP.bikey': 'vpp key'});
    final instance = await rig.instance();
    keyFile(instance, 'admin.bikey')
      ..createSync(recursive: true)
      ..writeAsStringSync('the admin key');
    await rig.setMods(instance, [ModSpec(cfMod), ModSpec(vppMod)]);
    await rig.apply(instance);
    expect(rig.keys(instance)..sort(), [
      'CF.bikey',
      'VPP.bikey',
      'admin.bikey',
    ]);

    // The only mod that provides VPP.bikey is removed and the mods staged.
    await rig.setMods(instance, [ModSpec(cfMod)]);
    final done = await rig.apply(instance);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    expect(rig.keys(instance)..sort(), ['CF.bikey', 'admin.bikey']);
    expect(
      keyFile(instance, 'admin.bikey').readAsStringSync(),
      'the admin key',
    );
    // The mod's link went too.
    expect(isLink(rig.staged(instance, '@VPP')), isFalse);
    expect(Directory(rig.staged(instance, '@VPP')).existsSync(), isFalse);
  });

  test('identical_key_is_adopted', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'CF');
    rig.steam.files[cfMod] = modWithKeys({'CF.bikey': 'cf key'});
    final instance = await rig.instance();
    // Already there with the mod's content: the daemon takes it over.
    keyFile(instance, 'CF.bikey')
      ..createSync(recursive: true)
      ..writeAsStringSync('cf key');
    await rig.setMods(instance, [ModSpec(cfMod)]);

    await rig.apply(instance);

    expect((await rig.mod(instance, cfMod)).warnings, isEmpty);
    await rig.setMods(instance, []);
    await rig.apply(instance);
    expect(keyFile(instance, 'CF.bikey').existsSync(), isFalse);
  });

  test('key_rule_too_broad', () async {
    final rig = await ModsRig.start();
    rig.item(cfMod, title: 'CF');
    // 1,025 files match `**/*.bikey`; a rule takes at most 1,024 per mod.
    rig.steam.files[cfMod] = modWithKeys({
      for (var i = 0; i < 1025; i++) 'k$i.bikey': 'k$i',
    });
    final instance = await rig.instance();
    await rig.setMods(instance, [ModSpec(cfMod)]);

    final done = await rig.apply(instance);

    expect(done.status, OperationStatus.failed);
    expect(done.resultReason, 'key_rule_too_broad');
    expect(done.resultMessage, contains('**/*.bikey'));
    expect(rig.keys(instance), isEmpty);
  });
}
