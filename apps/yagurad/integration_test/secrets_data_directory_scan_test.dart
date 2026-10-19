@Tags(['windows'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/instances/instance.dart';

import '../test/support/daemon_support.dart';
import '../test/support/secret_support.dart';
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
/// scanned and where a secret in any encoding was found.
({List<String> scanned, List<String> leaks}) scan(
  Iterable<String> roots,
  Iterable<String> values,
) {
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
}
