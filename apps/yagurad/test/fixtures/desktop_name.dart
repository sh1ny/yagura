// The window station and desktop the current process runs on, as
// `Station\Desktop`, or null where that cannot be told (not Windows). The
// fixtures record it so the `elevated` rows can see the separation of design
// D7 from outside the process.
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

String? currentDesktopName() {
  if (!Platform.isWindows) return null;
  try {
    final user32 = DynamicLibrary.open('user32.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final station = user32.lookupFunction<IntPtr Function(), int Function()>(
      'GetProcessWindowStation',
    )();
    final threadId = kernel32.lookupFunction<Uint32 Function(), int Function()>(
      'GetCurrentThreadId',
    )();
    final desktop = user32
        .lookupFunction<IntPtr Function(Uint32), int Function(int)>(
          'GetThreadDesktop',
        )(threadId);
    final info = user32
        .lookupFunction<
          Int32 Function(
            IntPtr,
            Int32,
            Pointer<Utf16>,
            Uint32,
            Pointer<Uint32>,
          ),
          int Function(int, int, Pointer<Utf16>, int, Pointer<Uint32>)
        >('GetUserObjectInformationW');
    String name(int handle) {
      final buffer = calloc<Uint16>(256).cast<Utf16>();
      final needed = calloc<Uint32>();
      try {
        if (info(handle, 2, buffer, 512, needed) == 0) return '?';
        return buffer.toDartString();
      } finally {
        calloc.free(buffer);
        calloc.free(needed);
      }
    }

    return '${name(station)}\\${name(desktop)}';
  } on Object {
    return null;
  }
}
