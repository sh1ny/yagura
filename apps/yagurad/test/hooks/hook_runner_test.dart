import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/errors.dart';
import 'package:yagurad/src/hooks/hooks.dart';

import 'hook_test_support.dart';
import '../support/temp_support.dart';

Matcher failsWith(String reason, {String? messageContains}) => throwsA(
  isA<YaguraException>()
      .having((e) => e.reason, 'reason', reason)
      .having(
        (e) => e.message,
        'message',
        messageContains == null ? anything : contains(messageContains),
      ),
);

Future<HookRunResult> run(
  Directory instance,
  String source, {
  HookPoint point = HookPoint.onPreStart,
  Duration deadline = const Duration(seconds: 5),
  HookHost? host,
}) => (host ?? HookHost()).run(
  invocationFor(instance, source, point: point, deadline: deadline),
);

void main() {
  group('hook points and results', () {
    test('onPreStart adds arguments and environment', () async {
      final result = await run(makeInstance(), '''
exports.onPreStart = (ctx) => ({args: ['-freezecheck'], env: {SteamAppId: '221100'}});
''');
      expect(result.ran, isTrue);
      expect(result.args, ['-freezecheck']);
      expect(result.env, {'SteamAppId': '221100'});
    });

    test('a hook that is not exported is skipped without a warning', () async {
      final result = await run(
        makeInstance(),
        'exports.onPreStart = () => ({});',
        point: HookPoint.onPostInstall,
      );
      expect(result.ran, isFalse);
      expect(result.logs, isEmpty);
    });

    test(
      'hooks may be top-level functions or module.exports members',
      () async {
        final instance = makeInstance();
        expect(
          (await run(
            instance,
            'function onPreStart() { return {args: ["a"]}; }',
          )).args,
          ['a'],
        );
        expect(
          (await run(
            instance,
            'module.exports = {onPreStart() { return {args: ["b"]}; }};',
          )).args,
          ['b'],
        );
      },
    );

    test('a hook returning nothing is an empty result', () async {
      final result = await run(
        makeInstance(),
        'exports.onPostStop = () => {};',
        point: HookPoint.onPostStop,
      );
      expect(result.ran, isTrue);
      expect(result.args, isNull);
    });

    test(
      'the context carries identity, paths, ports and masked secrets',
      () async {
        final result = await run(makeInstance(), '''
exports.onPreStart = (ctx) => ({args: [
  ctx.instanceId, ctx.pluginId, ctx.pluginVersion, ctx.os,
  ctx.paths.config, String(ctx.ports.game),
  JSON.stringify(ctx.settings.rconPassword)]});
''');
        expect(result.args, [
          'inst-1',
          'dayz',
          '1.0.0',
          'windows',
          'cfg',
          '2302',
          '{"secret":true,"set":false}',
        ]);
      },
    );

    test('yagura.log entries are returned', () async {
      final result = await run(makeInstance(), '''
exports.onPreStart = () => {
  yagura.log('starting');
  yagura.log('warn', 'careful');
  return {};
};
''');
      expect(result.logs, [
        {'level': 'info', 'message': 'starting'},
        {'level': 'warn', 'message': 'careful'},
      ]);
    });

    test('invalid result shape names the hook and the path', () async {
      await expectLater(
        run(
          makeInstance(),
          'exports.onPreStart = () => ({args: "-freezecheck"});',
        ),
        throwsA(
          isA<YaguraException>()
              .having((e) => e.reason, 'reason', 'hook_result_invalid')
              .having((e) => e.message, 'message', contains('onPreStart'))
              .having((e) => e.details['path'], 'path', 'args'),
        ),
      );
    });

    for (final (name, source, path) in [
      ('unknown key', 'exports.onPreStart = () => ({extra: 1});', 'extra'),
      ('args element', 'exports.onPreStart = () => ({args: [1]});', 'args[0]'),
      ('env value', 'exports.onPreStart = () => ({env: {A: 1}});', 'env.A'),
      (
        'file edit key',
        'exports.onPreStart = () => ({files: [{path: "a", format: "json", patch: {}, x: 1}]});',
        'files[0].x',
      ),
      (
        'file edit patch',
        'exports.onPreStart = () => ({files: [{path: "a", format: "json", patch: 1}]});',
        'files[0].patch',
      ),
      ('non-object result', 'exports.onPreStart = () => [1];', r'$'),
    ]) {
      test('rejects $name at $path', () async {
        await expectLater(
          run(makeInstance(), source),
          throwsA(
            isA<YaguraException>()
                .having((e) => e.reason, 'reason', 'hook_result_invalid')
                .having((e) => e.details['path'], 'path', path),
          ),
        );
      });
    }

    test('args and env are only allowed from onPreStart', () async {
      await expectLater(
        run(
          makeInstance(),
          'exports.onPostInstall = () => ({args: ["x"]});',
          point: HookPoint.onPostInstall,
        ),
        throwsA(
          isA<YaguraException>()
              .having((e) => e.reason, 'reason', 'hook_result_invalid')
              .having((e) => e.details['path'], 'path', 'args'),
        ),
      );
    });

    test(
      'an edit in an unsupported format fails and changes nothing',
      () async {
        final instance = makeInstance();
        final file = writeInstanceFile(instance, 'cfg.json', '{"a": 1}');
        await expectLater(
          run(instance, '''
exports.onPreStart = () => ({files: [
  {path: 'cfg.json', format: 'json', patch: {a: 2}},
  {path: 'server.ini', format: 'ini', patch: {a: 2}}]});
'''),
          failsWith(
            'unsupported_in_this_version',
            messageContains: 'server.ini',
          ),
        );
        expect(file.readAsStringSync(), '{"a": 1}');
      },
    );
  });

  group('deadline, memory and errors', () {
    test('an infinite loop is interrupted at the deadline', () async {
      final host = HookHost();
      final watch = Stopwatch()..start();
      await expectLater(
        run(
          makeInstance(),
          'exports.onPreStart = () => { while (true) {} };',
          deadline: const Duration(milliseconds: 300),
          host: host,
        ),
        failsWith('hook_timeout', messageContains: 'onPreStart'),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
      // The runtime was freed and the slot returned.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(host.runningWorkers, 0);
      expect(host.leakedWorkers, 0);
    });

    test('a script cannot swallow the interrupt', () async {
      await expectLater(
        run(
          makeInstance(),
          'exports.onPreStart = () => { try { while (true) {} } catch (e) { return {}; } };',
          deadline: const Duration(milliseconds: 200),
        ),
        failsWith('hook_timeout'),
      );
    });

    test('a 200 MiB string fails with hook_out_of_memory', () async {
      await expectLater(
        run(
          makeInstance(),
          "exports.onPreStart = () => { const s = 'x'.repeat(200 * 1024 * 1024); return {args: [s]}; };",
        ),
        failsWith('hook_out_of_memory'),
      );
    });

    test('a 2 MiB result fails with hook_result_too_large', () async {
      await expectLater(
        run(
          makeInstance(),
          "exports.onPreStart = () => ({args: ['x'.repeat(2 * 1024 * 1024)]});",
        ),
        failsWith('hook_result_too_large', messageContains: '1 MiB'),
      );
    });

    test(
      'a thrown error reports message and stack with file and line',
      () async {
        const source = '''
// line 1
// line 2
exports.onPreStart = function () {
  throw new Error("missing cfg");
};
''';
        await expectLater(
          run(makeInstance(), source),
          throwsA(
            isA<YaguraException>()
                .having((e) => e.reason, 'reason', 'hook_error')
                .having((e) => e.message, 'message', 'missing cfg')
                .having((e) => e.details['hook'], 'hook', 'onPreStart')
                .having(
                  (e) => e.details['stack'],
                  'stack',
                  contains('hooks.js:4'),
                ),
          ),
        );
      },
    );

    test('a syntax error is reported with its line', () async {
      await expectLater(
        run(makeInstance(), 'var a = 1;\nvar b = ;\n'),
        throwsA(
          isA<YaguraException>()
              .having((e) => e.reason, 'reason', 'hook_syntax_error')
              .having(
                (e) => '${e.message} ${e.details['stack']}',
                'location',
                contains('hooks.js:2'),
              ),
        ),
      );
    });

    test('a promise result is refused', () async {
      await expectLater(
        run(makeInstance(), 'exports.onPreStart = async () => ({});'),
        failsWith('hook_error', messageContains: 'synchronous'),
      );
    });

    test(
      'hooks have no network, process, timer or environment access',
      () async {
        final result = await run(makeInstance(), '''
exports.onPreStart = () => ({args: [
  typeof fetch, typeof XMLHttpRequest, typeof setTimeout, typeof process,
  typeof require, typeof std, typeof os, typeof console, typeof print]});
''');
        expect(result.args, everyElement('undefined'));
      },
    );

    test(
      'yagura.formats.json parses and serialises; other formats refuse',
      () async {
        final result = await run(makeInstance(), '''
exports.onPreStart = () => {
  const out = [];
  out.push(String(yagura.formats.json.parse('{"a": [1, 2]}').a[1]));
  out.push(yagura.formats.json.serialize({a: 1}));
  for (const format of ['ini', 'yaml']) {
    try { yagura.formats[format].parse('x'); out.push('no error'); }
    catch (e) { out.push(e.code); }
  }
  try { yagura.formats.json.parse('{bad'); } catch (e) { out.push(e.code); }
  return {args: out};
};
''');
        expect(result.args, [
          '2',
          '{"a":1}',
          'unsupported_in_this_version',
          'unsupported_in_this_version',
          'invalid_json',
        ]);
      },
    );

    test('yagura.fs.readText reads a file inside the instance', () async {
      final instance = makeInstance();
      writeInstanceFile(instance, 'notes/a.txt', 'héllo');
      final result = await run(instance, '''
exports.onPreStart = () => {
  let missing;
  try { yagura.fs.readText('notes/none.txt'); } catch (e) { missing = e.code; }
  return {args: [yagura.fs.readText('notes/a.txt'), missing]};
};
''');
      expect(result.args, ['héllo', 'ENOENT']);
    });

    test(
      'a link inside the instance to outside cannot be read through',
      () async {
        final instance = makeInstance();
        final outside = createCanonicalTempSync('yagura_outside_');
        addTearDown(() => outside.deleteSync(recursive: true));
        File(p.join(outside.path, 'secret.txt')).writeAsStringSync('secret');
        try {
          Link(p.join(instance.path, 'cfg')).createSync(outside.path);
        } on FileSystemException {
          markTestSkipped('this account cannot create links');
          return;
        }
        final result = await run(instance, '''
exports.onPreStart = () => {
  try { return {args: [yagura.fs.readText('cfg/secret.txt')]}; }
  catch (e) { return {args: [e.code]}; }
};
''');
        expect(result.args, ['sandbox_violation']);
      },
    );
  });

  group('workers', () {
    test('slots are bounded to four real concurrent hooks', () async {
      final host = HookHost();
      final calls = [
        for (var i = 0; i < 6; i++)
          run(
            makeInstance(),
            'exports.onPreStart = () => { const t = Date.now(); while (Date.now() - t < 150) {} return {args: ["$i"]}; };',
            host: host,
          ),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(host.runningWorkers, lessThanOrEqualTo(4));
      final results = await Future.wait(calls);
      expect(results.map((r) => r.args!.single).toSet(), {
        '0',
        '1',
        '2',
        '3',
        '4',
        '5',
      });
      // A slot is released when the isolate exits, just after its reply.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(host.runningWorkers, 0);
    });

    test(
      'cancelling a call that waits for a slot fails it with interrupted',
      () async {
        final host = HookHost(maxWorkers: 1);
        final busy = run(
          makeInstance(),
          'exports.onPreStart = () => { const t = Date.now(); while (Date.now() - t < 300) {} return {}; };',
          host: host,
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final cancel = Future<void>.delayed(const Duration(milliseconds: 50));
        await expectLater(
          host.run(
            invocationFor(makeInstance(), 'exports.onPreStart = () => ({});'),
            cancel: cancel,
          ),
          failsWith('interrupted'),
        );
        await busy;
      },
    );

    test('two leaked workers degrade the runtime until restart', () async {
      final host = HookHost(
        degradedAt: 2,
        watchdogGrace: const Duration(milliseconds: 20),
        leakGrace: const Duration(milliseconds: 50),
        launcher: (request) async => _StuckWorker(),
      );
      for (var i = 0; i < 2; i++) {
        await expectLater(
          run(
            makeInstance(),
            'ignored',
            deadline: const Duration(milliseconds: 20),
            host: host,
          ),
          failsWith('hook_timeout'),
        );
      }
      expect(host.degraded, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(host.leakedWorkers, 2);
      expect(host.degraded, isTrue);
      await expectLater(
        run(makeInstance(), 'exports.onPreStart = () => ({});', host: host),
        failsWith('hook_runtime_degraded'),
      );
    });
  });
}

/// A worker that never replies and never exits, like one stuck in native code.
class _StuckWorker implements HookWorker {
  @override
  final Future<Map<String, Object?>> result =
      Completer<Map<String, Object?>>().future;

  @override
  final Future<void> exited = Completer<void>().future;

  @override
  void kill() {}
}
