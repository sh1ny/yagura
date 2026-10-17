import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'win32.dart';

/// Why this process cannot start the relay outside its job, or null when it
/// can (spike 1.3). `GetLastError` is unreliable through plain `dart:ffi`, so
/// the answer comes from the job's limit flags: a process in a job without
/// `JOB_OBJECT_LIMIT_BREAKAWAY_OK` makes `CREATE_BREAKAWAY_FROM_JOB` fail.
///
/// Windows only.
String? breakawayRestriction() {
  final win32 = Win32.instance;
  final inJob = calloc<Int32>();
  final info = calloc<Uint8>(Win32.jobExtendedLimitSize);
  final returned = calloc<Uint32>();
  try {
    if (win32.isProcessInJob(win32.getCurrentProcess(), 0, inJob) == 0 ||
        inJob.value == 0) {
      return null;
    }
    if (win32.queryInformationJobObject(
          0,
          Win32.jobExtendedLimitInformation,
          info.cast(),
          Win32.jobExtendedLimitSize,
          returned,
        ) ==
        0) {
      // The job cannot be inspected; the spawn will say if it is refused.
      return null;
    }
    final limitFlags =
        (info.cast<Uint32>() + Win32.jobLimitFlagsOffset ~/ 4).value;
    if (limitFlags & (Win32.jobBreakawayOk | Win32.jobSilentBreakawayOk) != 0) {
      return null;
    }
    return 'this process runs inside a job object (limit flags '
        '0x${limitFlags.toRadixString(16)}) that does not allow breakaway '
        '(neither JOB_OBJECT_LIMIT_BREAKAWAY_OK nor SILENT_BREAKAWAY_OK is set), so CREATE_BREAKAWAY_FROM_JOB '
        'is refused and a server started from here would die with the job';
  } finally {
    calloc.free(inJob);
    calloc.free(info);
    calloc.free(returned);
  }
}
