// Self-test of the fake SteamCMD's login transcripts and output timing
// (task 1.2; design A1, D2, D15; docs/spikes/m3-steam-guard.md).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/steam/patterns.g.dart';
import 'package:yaml/yaml.dart';

final _script = p.absolute(
  'test',
  'fixtures',
  'fake_steamcmd',
  'fake_steamcmd.dart',
);

const _banner = [
  'Steam Console Client (c) Valve Corporation - version 1730000000',
  "-- type 'quit' to exit --",
];

/// The `login` group's rule (patterns.yaml): outcomes in table order, the
/// first that any stdout line matches wins.
String? _classify(List<String> lines) {
  final login = (loadYaml(steamPatternsYaml) as YamlMap)['login'] as YamlMap;
  for (final outcome in login['outcomes'] as YamlList) {
    final match = RegExp((outcome as YamlMap)['match'] as String);
    if (lines.any(match.hasMatch)) return outcome['kind'] as String;
  }
  return null;
}

List<String> _lines(String text) => const LineSplitter().convert(text);

Future<(int, List<String>)> _run(
  List<String> args,
  Directory cwd,
  Map<String, String> env,
) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    [_script, ...args],
    workingDirectory: cwd.path,
    environment: env,
    stdoutEncoding: utf8,
  );
  return (result.exitCode, _lines(result.stdout as String));
}

/// A run that is still going, with what it has written to stdout so far.
class _Live {
  _Live._(this.process, this.cwd);

  static Future<_Live> start(
    List<String> args,
    Directory cwd,
    Map<String, String> env,
  ) async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      [_script, ...args],
      workingDirectory: cwd.path,
      environment: env,
    );
    final live = _Live._(process, cwd);
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(live.stdout.add);
    process.stderr.drain<void>();
    return live;
  }

  final Process process;
  final Directory cwd;
  final stdout = <String>[];

  File log(String name) => File(p.join(cwd.path, 'logs', name));

  List<String> logLines(String name) =>
      log(name).existsSync() ? _lines(log(name).readAsStringSync()) : const [];

  /// Waits until [name] has a line containing [text].
  Future<void> until(String name, String text) async {
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (!logLines(name).any((l) => l.contains(text))) {
      if (DateTime.now().isAfter(end)) fail('$name never had "$text"');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('fake_steamcmd_lg_'));
  tearDown(() => root.deleteSync(recursive: true));

  const real = {'FAKE_STEAMCMD_REAL_OUTPUT': '1'};

  group('login transcripts', () {
    // name: (exit code, intended outcome, a line it must print)
    const transcripts = {
      'email_code_asked': (
        5,
        'guard_email',
        'Steam Guard code:ERROR (Account Logon Denied)',
      ),
      'code_accepted': (0, 'ok', 'Steam Guard code provided.'),
      'mobile_approved': (0, 'ok', 'Waiting for confirmation...'),
      'cached_ok': (0, 'ok', 'Logging in using cached credentials.'),
      'cached_missing': (5, 'reauth_needed', 'Cached credentials not found.'),
      'wrong_password': (5, 'login_invalid', 'ERROR (Invalid Password)'),
      'rate_limit': (5, 'rate_limited', 'ERROR (Rate Limit Exceeded)'),
      'wrong_code': (5, 'guard_invalid', 'ERROR (Invalid Login Auth Code)'),
      'authenticator_code': (5, 'guard_authenticator', 'Two-factor code:'),
    };
    for (final MapEntry(key: name, value: (code, kind, line))
        in transcripts.entries) {
      for (final (label, extra) in [
        ('plain', <String, String>{}),
        ('held back', real),
      ]) {
        test('$name ($label): exit $code, classifies as $kind', () async {
          final (exitCode, out) = await _run(
            ['+login', 'alice', 'pw', '+quit'],
            root,
            {
              'FAKE_STEAMCMD_LOGIN': name,
              'FAKE_STEAMCMD_APPROVAL_DELAY_MS': '50',
              'FAKE_STEAMCMD_WAITING_MS': '20',
              ...extra,
            },
          );
          expect(exitCode, code);
          expect(out, contains(line));
          expect(_classify(out), kind);
        });
      }
    }

    test('mobile_approved prints the mobile lines, then the OK line', () async {
      final (code, out) = await _run(
        ['+login', 'alice', 'pw', '+quit'],
        root,
        {'FAKE_STEAMCMD_LOGIN': 'mobile_approved'},
      );
      expect(code, 0);
      expect(
        out,
        containsAllInOrder([
          'This account is protected by a Steam Guard mobile authenticator.',
          'Please confirm the login in the Steam Mobile app on your phone.',
          'Waiting for confirmation...',
          "Logging in user 'alice' [U:1:0] to Steam Public...OK",
        ]),
      );
    });

    test('a login script rule can name a transcript', () async {
      final script = File(p.join(root.path, 'script.json'))
        ..writeAsStringSync(
          jsonEncode({
            'rules': [
              {'user': 'bob', 'scenario': 'rate_limit'},
            ],
            'default': {'scenario': 'cached_ok'},
          }),
        );
      final env = {'FAKE_STEAMCMD_LOGIN_SCRIPT': script.path};
      final (bobCode, bob) = await _run(['+login', 'bob', '+quit'], root, env);
      final (annCode, ann) = await _run(['+login', 'ann', '+quit'], root, env);
      expect((bobCode, _classify(bob)), (5, 'rate_limited'));
      expect((annCode, _classify(ann)), (0, 'ok'));
    });

    test('a successful transcript goes on with the install', () async {
      final (code, out) = await _run(
        ['+login', 'alice', '+app_update', '1', '+quit'],
        root,
        {'FAKE_STEAMCMD_LOGIN': 'cached_ok'},
      );
      expect(code, 0);
      expect(out, contains("Success! App '1' fully installed."));
    });

    test('a failed transcript ends the run before the install', () async {
      final (code, out) = await _run(
        ['+login', 'alice', 'pw', '+app_update', '1', '+quit'],
        root,
        {'FAKE_STEAMCMD_LOGIN': 'wrong_password'},
      );
      expect(code, 5);
      expect(out.any((l) => l.startsWith('Success!')), isFalse);
    });

    test('an unknown transcript name fails loudly', () async {
      final (code, _) = await _run(
        ['+login', 'alice', '+quit'],
        root,
        {'FAKE_STEAMCMD_LOGIN': 'nope'},
      );
      expect(code, isNot(0));
    });
  });

  test('echoes the command line', () async {
    final (_, out) = await _run(
      ['+login', 'alice', '+quit'],
      root,
      {'FAKE_STEAMCMD_LOGIN': 'cached_ok', 'FAKE_STEAMCMD_ECHO_ARGV': '1'},
    );
    expect(out, contains('Command line: +login alice +quit'));
  });

  group('output timing', () {
    test('stdout arrives at exit; console_log.txt grows live', () async {
      final run = await _Live.start(
        ['+login', 'alice', 'pw', '+quit'],
        root,
        {
          ...real,
          'FAKE_STEAMCMD_LOGIN': 'mobile_approved',
          'FAKE_STEAMCMD_APPROVAL_DELAY_MS': '1500',
          'FAKE_STEAMCMD_WAITING_MS': '200',
        },
      );
      await run.until('console_log.txt', 'Waiting for confirmation...');
      // The run is still waiting: stdout holds the banner only.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(run.stdout, _banner);
      final console = run.logLines('console_log.txt');
      expect(console.take(2), [for (final b in _banner) endsWith('] $b')]);
      for (final line in console) {
        expect(line, matches(RegExp(r'^\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\] ')));
      }
      expect(await run.process.exitCode, 0);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(run.stdout.take(2), _banner);
      expect(
        run.stdout,
        contains("Logging in user 'alice' [U:1:0] to Steam Public...OK"),
      );
      expect(_classify(run.stdout), 'ok');
      // stdout is the log without its prefixes.
      expect(
        run.logLines('console_log.txt').map((l) => l.substring(22)).toList(),
        run.stdout,
      );
    });

    test(
      'connection_log.txt gets Waiting for confirmation repeatedly',
      () async {
        final (code, _) = await _run(
          ['+login', 'alice', 'pw', '+quit'],
          root,
          {
            ...real,
            'FAKE_STEAMCMD_LOGIN': 'mobile_approved',
            'FAKE_STEAMCMD_APPROVAL_DELAY_MS': '700',
            'FAKE_STEAMCMD_WAITING_MS': '100',
          },
        );
        expect(code, 0);
        final conn = _lines(
          File(p.join(root.path, 'logs', 'connection_log.txt'))
              .readAsStringSync(),
        );
        final waiting = conn.where(
          (l) => l.endsWith('] Waiting for confirmation'),
        );
        expect(waiting.length, inInclusiveRange(4, 9));
        expect(
          conn.last,
          endsWith('] PollAuthSessionStatus succeeded and has refresh token'),
        );
      },
    );

    test('mobile_never waits until killed, with nothing on stdout', () async {
      final run = await _Live.start(
        ['+login', 'alice', 'pw', '+quit'],
        root,
        {
          ...real,
          'FAKE_STEAMCMD_LOGIN': 'mobile_never',
          'FAKE_STEAMCMD_WAITING_MS': '50',
        },
      );
      await run.until('connection_log.txt', 'Waiting for confirmation');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final exited = run.process.exitCode.then((_) => true);
      expect(
        await Future.any([
          exited,
          Future<bool>.delayed(const Duration(milliseconds: 200), () => false),
        ]),
        isFalse,
      );
      expect(
        run.logLines('connection_log.txt').length,
        greaterThanOrEqualTo(3),
      );
      run.process.kill();
      await exited;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(run.stdout, _banner);
    });

    test('install progress is in console_log.txt while stdout waits', () async {
      final run = await _Live.start(
        ['+login', 'anonymous', '+app_update', '1', '+quit'],
        root,
        {...real, 'FAKE_STEAMCMD_DELAY_MS': '150'},
      );
      await run.until('console_log.txt', 'downloading, progress: 25.00');
      expect(run.stdout, _banner);
      expect(await run.process.exitCode, 0);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(run.stdout.any((l) => l.contains('progress: 100.00')), isTrue);
      expect(run.stdout.last, "Success! App '1' fully installed.");
    });

    test('plain mode keeps writing stdout live and no logs', () async {
      final run = await _Live.start(
        ['+login', 'anonymous', '+app_update', '1', '+quit'],
        root,
        {'FAKE_STEAMCMD_DELAY_MS': '150'},
      );
      final end = DateTime.now().add(const Duration(seconds: 20));
      while (!run.stdout.any((l) => l.contains('progress: 25.00'))) {
        if (DateTime.now().isAfter(end)) fail('no live progress on stdout');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(await run.process.exitCode, 0);
      expect(Directory(p.join(root.path, 'logs')).existsSync(), isFalse);
    });

    test('workshop progress follows the same timing', () async {
      final run = await _Live.start(
        ['+login', 'anonymous', '+workshop_download_item', '1', '2', '+quit'],
        root,
        {...real, 'FAKE_STEAMCMD_WORKSHOP_PROGRESS': '1'},
      );
      expect(await run.process.exitCode, 0);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(run.stdout.take(2), _banner);
      expect(run.stdout.where(_banner.contains), hasLength(2));
      final console = run.logLines('console_log.txt');
      expect(
        console.where((l) => l.contains('downloading, progress:')),
        hasLength(3),
      );
    });
  });

  group('log rotation at start', () {
    void seed() {
      for (final name in ['console_log.txt', 'connection_log.txt']) {
        File(p.join(root.path, 'logs', name))
          ..createSync(recursive: true)
          ..writeAsStringSync('[2020-01-01 00:00:00] old $name\n');
      }
    }

    test('rotate renames each log and starts a new one', () async {
      seed();
      await _run(
        ['+login', 'alice', '+quit'],
        root,
        {
          ...real,
          'FAKE_STEAMCMD_LOGIN': 'cached_ok',
          'FAKE_STEAMCMD_ROTATE_LOGS': 'rotate',
        },
      );
      String read(String name) =>
          File(p.join(root.path, 'logs', name)).readAsStringSync();
      expect(read('console_log_prev.txt'), contains('old console_log.txt'));
      expect(
        read('connection_log_prev.txt'),
        contains('old connection_log.txt'),
      );
      expect(read('console_log.txt'), isNot(contains('old')));
      expect(read('console_log.txt'), contains('Logging in using cached'));
      expect(
        File(p.join(root.path, 'logs', 'connection_log.txt')).existsSync(),
        isFalse,
      );
    });

    test('truncate empties each log before the run writes', () async {
      seed();
      await _run(
        ['+login', 'alice', '+quit'],
        root,
        {
          ...real,
          'FAKE_STEAMCMD_LOGIN': 'cached_ok',
          'FAKE_STEAMCMD_ROTATE_LOGS': 'truncate',
        },
      );
      String read(String name) =>
          File(p.join(root.path, 'logs', name)).readAsStringSync();
      expect(read('connection_log.txt'), isEmpty);
      expect(read('console_log.txt'), isNot(contains('old')));
      expect(read('console_log.txt'), contains('Logging in using cached'));
    });
  });

  test('a silent run neither exits nor writes until killed', () async {
    final run = await _Live.start(
      ['+login', 'alice', 'pw', '+quit'],
      root,
      {
        ...real,
        'FAKE_STEAMCMD_SILENT': '1',
        'FAKE_STEAMCMD_LOGIN': 'cached_ok',
      },
    );
    final exited = run.process.exitCode.then((_) => true);
    expect(
      await Future.any([
        exited,
        Future<bool>.delayed(const Duration(seconds: 1), () => false),
      ]),
      isFalse,
    );
    expect(run.stdout, isEmpty);
    expect(Directory(p.join(root.path, 'logs')).existsSync(), isFalse);
    run.process.kill();
    await exited;
  });
}
