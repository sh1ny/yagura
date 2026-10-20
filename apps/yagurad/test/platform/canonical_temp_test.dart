import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/platform/win32_paths.dart';

import '../support/temp_support.dart';

final int Function(Pointer<Utf16>, Pointer<Utf16>, int) _getShortPathName =
    DynamicLibrary.open('kernel32.dll').lookupFunction<
      Uint32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
      int Function(Pointer<Utf16>, Pointer<Utf16>, int)
    >('GetShortPathNameW');

/// The 8.3 form of [path] (which must exist), or [path] when the volume keeps
/// no short names.
String _shortPath(String path) => using((arena) {
  const capacity = 32768;
  final buffer = arena<Uint16>(capacity).cast<Utf16>();
  final length = _getShortPathName(
    path.toNativeUtf16(allocator: arena),
    buffer,
    capacity,
  );
  return length == 0 || length > capacity
      ? path
      : buffer.toDartString(length: length);
});

void main() {
  const onlyWindows = 'short names are a Windows thing';
  final skip = Platform.isWindows ? false : onlyWindows;

  test('a_short_name_path_resolves_to_the_long_one_the_daemon_reports', () {
    final temp = canonicalSystemTemp();
    final dir = Directory(p.join(temp.path, 'yagurad canonical long name'))
      ..createSync();
    addTearDown(() => dir.deleteSync());
    final short = _shortPath(dir.path);
    if (p.equals(short, dir.path)) {
      markTestSkipped('this volume keeps no 8.3 names');
      return;
    }

    expect(p.equals(short, dir.path), isFalse, reason: 'the paths differ');
    // What a daemon canonicalizes the short form to is the long form, so the
    // test directory must be built from the long form to compare equal.
    expect(
      resolveExistingPrefix(p.join(short, 'not', 'yet')).toLowerCase(),
      p.join(dir.path, 'not', 'yet').toLowerCase(),
    );
  }, skip: skip);

  test('the_test_temp_directory_is_its_own_canonical_form', () {
    final temp = createCanonicalTempSync('yagurad_canonical_');
    addTearDown(() => temp.deleteSync(recursive: true));

    expect(resolveExistingPrefix(temp.path), temp.path);
  }, skip: skip);
}
