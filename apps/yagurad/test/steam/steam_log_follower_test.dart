import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/files/files.dart';
import 'package:yagurad/src/steam/scrubber.dart';
import 'package:yagurad/src/steam/steam_log_follower.dart';

void main() {
  late Directory root;
  late ConfinedFs fs;
  late File log;
  late List<String> seen;

  setUp(() {
    root = Directory.systemTemp.createTempSync('yagura_follower');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory(p.join(root.path, 'logs')).createSync();
    fs = ConfinedFs(root.path);
    log = File(p.join(root.path, 'logs', 'console_log.txt'));
    seen = [];
  });

  SteamLogFollower follow({bool stripTimestamp = false, Scrubber? scrubber}) =>
      SteamLogFollower(
        fs: fs,
        path: 'logs/console_log.txt',
        onLine: seen.add,
        stripTimestamp: stripTimestamp,
        scrubber: scrubber,
        pollInterval: const Duration(hours: 1),
      );

  void append(String text) =>
      log.writeAsStringSync(text, mode: FileMode.append, flush: true);

  test('delivers the lines written after it started, not the old ones', () {
    append('old\n');
    final follower = follow()..start();
    addTearDown(follower.stop);
    append('one\ntwo\n');

    follower.poll();

    expect(seen, ['one', 'two']);
    follower.poll();
    expect(seen, hasLength(2), reason: 'a line is delivered once');
  });

  test('a line is held until its end arrives; CR is dropped', () {
    final follower = follow()..start();
    addTearDown(follower.stop);
    append('half');
    follower.poll();
    expect(seen, isEmpty);

    append(' done\r\nnext\n');
    follower.poll();

    expect(seen, ['half done', 'next']);
  });

  test('a line over 4096 bytes is cut and the rest is dropped', () {
    final follower = follow()..start();
    addTearDown(follower.stop);
    append('${'a' * 5000}\nshort\n');

    follower.poll();

    expect(seen, hasLength(2));
    expect(seen.first, 'a' * SteamLogFollower.maxLineBytes);
    expect(seen.last, 'short');
  });

  test('one poll reads at most 64 KiB', () {
    final follower = follow()..start();
    addTearDown(follower.stop);
    final line = '${'x' * 99}\n';
    append(line * 1000);

    follower.poll();

    expect(seen.length * line.length, lessThanOrEqualTo(64 * 1024));
    expect(seen.length * line.length, greaterThan(64 * 1024 - line.length));
    follower.poll();
    expect(seen.length, greaterThan(655));
    follower.poll();
    expect(seen, hasLength(1000), reason: 'the rest follows on later polls');
  });

  test('the timestamp prefix of console_log lines is stripped', () {
    final follower = follow(stripTimestamp: true)..start();
    addTearDown(follower.stop);
    append('[2026-10-20 08:09:10] Logging in\nno prefix\n');

    follower.poll();

    expect(seen, ['Logging in', 'no prefix']);
  });

  test('a file that is truncated is read again from its start', () {
    append('before\n');
    final follower = follow()..start();
    addTearDown(follower.stop);
    append('first line of the run\n');
    follower.poll();

    log.writeAsStringSync('new\n');
    follower.poll();

    expect(seen, ['first line of the run', 'new']);
  });

  test('a file replaced by another file is read from its start', () {
    append('old content that is rather long\n');
    final follower = follow()..start();
    addTearDown(follower.stop);
    log.renameSync('${log.path}.prev');
    // Longer than what was reached, so only the file id tells it apart.
    append('a replacement file that is a lot longer than the old one\n');

    follower.poll();

    expect(seen, ['a replacement file that is a lot longer than the old one']);
  }, skip: Platform.isWindows ? false : 'the file id is an NTFS notion');

  test('a missing file is no signal, and its first lines are read', () {
    final follower = follow()..start();
    addTearDown(follower.stop);
    follower.poll();
    expect(seen, isEmpty);

    append('appeared\n');
    follower.poll();

    expect(seen, ['appeared']);
  });

  test('a file that cannot be read is no signal', () {
    Directory(log.path).createSync();
    final follower = follow()..start();
    addTearDown(follower.stop);

    expect(follower.poll, returnsNormally);
    expect(seen, isEmpty);
  });

  test('lines are scrubbed before anyone sees them, the last 5 are kept', () {
    final follower = follow(scrubber: Scrubber(['s3cret']))..start();
    addTearDown(follower.stop);
    append('login s3cret ok\n');
    for (var i = 1; i <= 6; i++) {
      append('line $i\n');
    }

    follower.poll();

    expect(seen.first, 'login *** ok');
    expect(follower.lastLines, [for (var i = 2; i <= 6; i++) 'line $i']);
  });

  test('stop polls once more and hands over an unfinished last line', () {
    final follower = follow()..start();
    append('last\nunfinished');

    follower.stop();

    expect(seen, ['last', 'unfinished']);
  });

  test('the bytes of a multi-byte character may arrive in two polls', () {
    final follower = follow()..start();
    addTearDown(follower.stop);
    final bytes = utf8.encode('café\n');
    log.writeAsBytesSync(bytes.sublist(0, 4), mode: FileMode.append);
    follower.poll();
    log.writeAsBytesSync(bytes.sublist(4), mode: FileMode.append);
    follower.poll();

    expect(seen, ['café']);
  });
}
