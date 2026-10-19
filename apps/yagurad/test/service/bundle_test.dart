import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/service/bundle.dart';
import 'package:yagurad/src/service/winsw_config.dart';
import 'package:yagurad/src/version.dart';

import '../support/service_support.dart';
import '../support/temp_support.dart';

void main() {
  group('the running bundle', () {
    test('is_the_directory_above_bin', () {
      final bundle = makeBundle('0.1.0');

      final running = Bundle.running(
        executable: p.join(bundle.root, 'bin', 'yagurad.exe'),
      );

      expect(running.root, bundle.root);
      expect(running.version, daemonVersion);
    });

    test('takes_its_version_from_a_VERSION_file', () {
      final bundle = makeBundle('0.1.0');
      File(p.join(bundle.root, 'VERSION')).writeAsStringSync(' 2.3.4\r\n');

      final running = Bundle.running(
        executable: p.join(bundle.root, 'bin', 'yagurad.exe'),
      );

      expect(running.version, '2.3.4');
    });

    test('a_VERSION_that_is_not_a_version_is_bundle_invalid', () async {
      final bundle = makeBundle('0.1.0');
      File(p.join(bundle.root, 'VERSION')).writeAsStringSync('..\\evil');

      final e = await failureOf(
        () async => Bundle.running(
          executable: p.join(bundle.root, 'bin', 'yagurad.exe'),
        ),
      );

      expect(e.reason, 'bundle_invalid');
    });

    test('an_executable_that_is_not_yagurad_is_bundle_invalid', () async {
      // `dart run` and `dart test` run the Dart VM, not a bundle.
      final e = await failureOf(
        () async => Bundle.running(executable: Platform.resolvedExecutable),
      );

      expect(e.reason, 'bundle_invalid');
      expect(e.message, contains('yagurad.exe'));
    });
  });

  group('validate', () {
    test('accepts_the_pinned_winsw_and_the_template', () {
      makeBundle('0.1.0').validate();
    });

    test('refuses_a_missing_winsw', () async {
      final bundle = makeBundle('0.1.0', withWinsw: false);

      final e = await failureOf(() async => bundle.validate());

      expect(e.reason, 'bundle_invalid');
      expect(e.message, contains('WinSW.NET461.exe'));
    });

    test('refuses_a_winsw_that_is_not_the_pinned_one', () async {
      final bundle = makeBundle('0.1.0');
      File(bundle.winswExecutable).writeAsStringSync('another binary');

      final e = await failureOf(() async => bundle.validate());

      expect(e.reason, 'bundle_invalid');
      expect(e.message, contains(winswSha256));
    });

    test('refuses_a_missing_template', () async {
      final bundle = makeBundle('0.1.0');
      File(bundle.winswTemplate).deleteSync();

      final e = await failureOf(() async => bundle.validate());

      expect(e.reason, 'bundle_invalid');
    });
  });

  test('copy_takes_bin_and_lib_and_not_winsw', () {
    final bundle = makeBundle('0.1.0');
    final target = createCanonicalTempSync('yagurad_copy_');
    addTearDown(() => target.deleteSync(recursive: true));
    final destination = p.join(target.path, '0.1.0');

    bundle.copyTo(destination);

    expect(
      File(p.join(destination, 'bin', 'yagurad.exe')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(destination, 'lib', 'sqlite3.dll')).existsSync(),
      isTrue,
    );
    expect(Directory(p.join(destination, 'winsw')).existsSync(), isFalse);
  });

  test('the_pinned_winsw_is_the_one_in_the_repository', () {
    final file = File(p.join(winswSourceDirectory, 'WinSW.NET461.exe'));

    expect(sha256.convert(file.readAsBytesSync()).toString(), winswSha256);
    // The README states the same version and hash.
    final readme = File(p.join(winswSourceDirectory, 'README.md'))
        .readAsStringSync();
    expect(readme, contains(winswSha256));
    expect(readme, contains(winswVersion));
  });
}
