import 'dart:io';

import 'package:yagurad/src/platform/win32_paths.dart';

/// The system temp directory under the name the daemon gives it.
///
/// A Windows runner's `TEMP` can hold an 8.3 short name
/// (`C:\Users\RUNNER~1\...`) while the daemon resolves every path it is given
/// to the long one (`C:\Users\runneradmin\...`), so a path built from the
/// short form never equals what the daemon reports. Tests that compare such
/// paths make their directories below this one.
Directory canonicalSystemTemp() {
  final temp = Directory.systemTemp;
  return Platform.isWindows
      ? Directory(resolveExistingPrefix(temp.path))
      : temp;
}

/// A new directory below [canonicalSystemTemp].
Directory createCanonicalTempSync([String prefix = '']) =>
    canonicalSystemTemp().createTempSync(prefix);

/// Deletes [dir], retrying for up to 2 s: on Windows a process that was just
/// killed can hold its working directory for a moment after its exit code
/// arrives.
Future<void> deleteWithRetry(Directory dir) async {
  for (var attempt = 1; ; attempt++) {
    try {
      dir.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 20) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
