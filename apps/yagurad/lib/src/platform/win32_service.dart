import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'win32.dart';
import 'win32_security.dart';

final DynamicLibrary _advapi = DynamicLibrary.open('advapi32.dll');

final int Function(Pointer<Utf16>, Pointer<Utf16>, int) _openScManager = _advapi
    .lookupFunction<
      IntPtr Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
      int Function(Pointer<Utf16>, Pointer<Utf16>, int)
    >('OpenSCManagerW');

final int Function(int, Pointer<Utf16>, int) _openService = _advapi
    .lookupFunction<
      IntPtr Function(IntPtr, Pointer<Utf16>, Uint32),
      int Function(int, Pointer<Utf16>, int)
    >('OpenServiceW');

final int Function(int, Pointer<Uint32>) _queryServiceStatus = _advapi
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)
    >('QueryServiceStatus');

final int Function(int) _closeServiceHandle = _advapi
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'CloseServiceHandle',
    );

/// `ERROR_SERVICE_DOES_NOT_EXIST`.
const errorServiceDoesNotExist = 1060;

/// `dwCurrentState` of `SERVICE_STATUS`.
const serviceStopped = 1;
const serviceStartPending = 2;
const serviceStopPending = 3;
const serviceRunning = 4;

/// The `dwCurrentState` of the service [name] as the service control manager
/// reports it, or null when no such service exists. Read only: it opens the
/// manager and the service for `SC_MANAGER_CONNECT` and
/// `SERVICE_QUERY_STATUS`, which any account may do.
int? queryServiceState(String name) {
  const scManagerConnect = 0x0001;
  const serviceQueryStatus = 0x0004;
  final serviceName = name.toNativeUtf16();
  // SERVICE_STATUS is seven DWORDs; the state is the second.
  final status = calloc<Uint32>(7);
  try {
    final manager = callReadingError(
      () => _openScManager(nullptr, nullptr, scManagerConnect),
      (h) => h == 0,
    );
    if (manager.value == 0) throw Win32Error('OpenSCManagerW', manager.error);
    try {
      final service = callReadingError(
        () => _openService(manager.value, serviceName, serviceQueryStatus),
        (h) => h == 0,
      );
      if (service.value == 0) {
        if (service.error == errorServiceDoesNotExist) return null;
        throw Win32Error('OpenServiceW', service.error);
      }
      try {
        final query = callReadingError(
          () => _queryServiceStatus(service.value, status),
          (r) => r == 0,
        );
        if (query.value == 0) {
          throw Win32Error('QueryServiceStatus', query.error);
        }
        return status[1];
      } finally {
        _closeServiceHandle(service.value);
      }
    } finally {
      _closeServiceHandle(manager.value);
    }
  } finally {
    calloc
      ..free(serviceName)
      ..free(status);
  }
}
