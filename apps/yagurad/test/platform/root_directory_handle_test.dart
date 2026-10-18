@Tags(['windows'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/platform/acl_writer.dart';
import 'package:yagurad/src/platform/win32_paths.dart';

import '../support/admin_support.dart';
import '../support/daemon_support.dart';

/// A junction at [link] leading to [target] (needs no privilege).
void junction(String link, String target) {
  final result = Process.runSync('cmd', ['/c', 'mklink', '/J', link, target]);
  expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
}

void main() {
  late Directory work;

  setUp(() {
    work = Directory.systemTemp.createTempSync('yagurad_handle_');
    addTearDown(() {
      // Junctions are removed without touching their targets.
      for (final entity in work.listSync()) {
        if (FileSystemEntity.isLinkSync(entity.path)) {
          Link(entity.path).deleteSync();
        }
      }
      work.deleteSync(recursive: true);
    });
  });

  PathRefused refusal(String path) {
    try {
      const WindowsAclWriter().open(path).close();
    } on PathRefused catch (e) {
      return e;
    }
    fail('$path was opened');
  }

  test('a_directory_is_opened_under_its_real_name', () {
    final dir = Directory(p.join(work.path, 'Real Name'))..createSync();

    final opened = const WindowsAclWriter().open(
      p.join(work.path, 'REAL NAME'),
    );
    addTearDown(opened.close);

    expect(opened.path.toLowerCase(), dir.path.toLowerCase());
    expect(opened.path, endsWith('Real Name'), reason: 'the case on disk');
  });

  test('a_held_directory_cannot_be_deleted_or_renamed', () {
    final dir = Directory(p.join(work.path, 'held'))..createSync();
    final opened = const WindowsAclWriter().open(dir.path);

    expect(() => dir.renameSync(p.join(work.path, 'moved')), throwsA(anything));
    expect(() => dir.deleteSync(), throwsA(anything));
    expect(dir.existsSync(), isTrue);

    opened.close();
    dir.renameSync(p.join(work.path, 'moved'));
  });

  test('a_junction_at_the_root_is_refused', () {
    final target = Directory(p.join(work.path, 'target'))..createSync();
    final link = p.join(work.path, 'link');
    junction(link, target.path);

    expect(refusal(link).why, contains('link'));
  });

  test('a_junction_in_a_parent_folder_is_refused', () {
    final target = Directory(p.join(work.path, 'target'))..createSync();
    Directory(p.join(target.path, 'sub')).createSync();
    final link = p.join(work.path, 'link');
    junction(link, target.path);

    final refused = refusal(p.join(link, 'sub'));

    expect(refused.why, contains('link'));
    expect(refused.why.toLowerCase(), contains('target'));
  });

  test('a_file_and_a_missing_path_are_refused', () {
    final file = File(p.join(work.path, 'file.txt'))..writeAsStringSync('x');

    expect(refusal(file.path).why, contains('not a directory'));
    expect(refusal(p.join(work.path, 'missing')).why, contains('not exist'));
  });

  test('the_descriptor_is_written_through_the_held_handle', () {
    final dir = Directory(p.join(work.path, 'protected'))..createSync();
    final opened = const WindowsAclWriter().open(dir.path);

    opened.writeDacl('D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;FA;;;WD)');
    opened.close();

    final acl = Process.runSync('icacls', [dir.path]).stdout as String;
    expect(acl, contains(r'NT AUTHORITY\SYSTEM:(OI)(CI)(F)'));
    expect(acl, contains('Everyone:(OI)(CI)(F)'));
    expect(acl, isNot(contains('(I)')), reason: 'protected: nothing inherited');
  });

  test('roots_add_refuses_a_junction_root_and_a_junction_on_the_way', () async {
    final env = TestEnv();
    final acl = OpeningAclWriter();
    final h = await AdminHarness.start(env, acl: acl);
    final target = Directory(p.join(work.path, 'target'))..createSync();
    Directory(p.join(target.path, 'sub')).createSync();
    final link = p.join(work.path, 'link');
    junction(link, target.path);

    for (final path in [link, p.join(link, 'sub')]) {
      final result = await h.run(['roots', 'add', path]);
      expect(result.code, isNot(0), reason: path);
      expect(result.err, contains('root_not_protected'), reason: '$result');
    }

    expect(acl.calls, isEmpty, reason: 'no descriptor was written');
    expect(
      (await h.run(['roots', 'list'])).out.trim().split('\n'),
      hasLength(1),
    );
  });

  test('a_directory_resolves_to_its_real_name_with_the_links_followed', () {
    final target = Directory(p.join(work.path, 'target'))..createSync();
    final link = p.join(work.path, 'link');
    junction(link, target.path);

    final resolved = resolveExistingPrefix(p.join(link, 'not', 'yet'));

    expect(
      resolved.toLowerCase(),
      p.join(target.path, 'not', 'yet').toLowerCase(),
    );
  });
}
