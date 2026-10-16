import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/hooks/hooks.dart';

import 'hook_test_support.dart';

void main() {
  test('file_edit_returned_and_applied_by_the_daemon', () async {
    final instance = makeInstance();
    const original =
        '{\n  "Before": 1,\n  "GeneralData": {\n    "disableBaseDamage": false,\n'
        '    "disablePersonalLight": true\n  },\n  "After": [1, 2]\n}\n';
    final file = writeInstanceFile(instance, 'cfggameplay.json', original);

    final result = await HookHost().run(
      invocationFor(instance, '''
exports.onPreStart = function () {
  return {files: [{
    path: 'cfggameplay.json',
    format: 'json',
    patch: {GeneralData: {disableBaseDamage: true}}
  }]};
};
'''),
    );

    expect(result.ran, isTrue);
    final content = file.readAsStringSync();
    expect(content, original.replaceFirst('false', 'true'));
    final json = jsonDecode(content) as Map<String, Object?>;
    expect((json['GeneralData']! as Map)['disableBaseDamage'], true);
    expect(json.keys, ['Before', 'GeneralData', 'After']);
    expect(Directory(instance.path).listSync().map((e) => p.basename(e.path)), [
      'cfggameplay.json',
    ], reason: 'no temporary file is left behind');
  });

  test('write_attempted_from_a_hook', () async {
    final instance = makeInstance();
    final result = await HookHost().run(
      invocationFor(instance, '''
exports.onPreStart = function () {
  const codes = [];
  for (const name of ['writeText', 'writeFile', 'remove', 'mkdir']) {
    try { yagura.fs[name]('x.txt', 'data'); codes.push('no error'); }
    catch (e) { codes.push(e.code); }
  }
  return {args: codes};
};
'''),
    );

    expect(result.args, everyElement('not_supported'));
    expect(File(p.join(instance.path, 'x.txt')).existsSync(), isFalse);
  });

  test('path_escape_refused', () async {
    final instance = makeInstance();
    // A file next to the instance that must stay unread.
    final outside = File(
      p.join(instance.parent.path, 'yagura_outside_secret.txt'),
    )..writeAsStringSync('top secret');
    addTearDown(() {
      if (outside.existsSync()) outside.deleteSync();
    });

    final result = await HookHost().run(
      invocationFor(instance, '''
exports.onPreStart = function () {
  const attempts = ['../../Windows/win.ini', '../yagura_outside_secret.txt'];
  const out = [];
  for (const path of attempts) {
    try { out.push(yagura.fs.readText(path)); }
    catch (e) { out.push(e.code); }
  }
  try { out.push(JSON.stringify(yagura.fs.list('..'))); }
  catch (e) { out.push(e.code); }
  return {args: out};
};
'''),
    );

    expect(result.args, [
      'sandbox_violation',
      'sandbox_violation',
      'sandbox_violation',
    ]);
  });
}
