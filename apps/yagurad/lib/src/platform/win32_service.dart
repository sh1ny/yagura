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

final int Function(
  int,
  int,
  int,
  int,
  Pointer<Uint8>,
  int,
  Pointer<Uint32>,
  Pointer<Uint32>,
  Pointer<Uint32>,
  Pointer<Utf16>,
)
_enumServicesStatusEx = _advapi
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Int32,
        Uint32,
        Uint32,
        Pointer<Uint8>,
        Uint32,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Utf16>,
      ),
      int Function(
        int,
        int,
        int,
        int,
        Pointer<Uint8>,
        int,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Utf16>,
      )
    >('EnumServicesStatusExW');

final int Function(int, Pointer<Uint8>, int, Pointer<Uint32>)
_queryServiceConfig = _advapi
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>),
      int Function(int, Pointer<Uint8>, int, Pointer<Uint32>)
    >('QueryServiceConfigW');

/// A service as the manager lists it: its name and the command line of its
/// image (`lpBinaryPathName`, which may be quoted and carry arguments).
typedef ServiceImage = ({String name, String imagePath});

/// Every Win32 service the manager knows with its image path, read through
/// `EnumServicesStatusExW` and `QueryServiceConfigW` (UTF-16 throughout, so a
/// path with any character comes back intact). Read only: it opens the
/// manager for `SC_MANAGER_ENUMERATE_SERVICE` and each service for
/// `SERVICE_QUERY_CONFIG`. A service that is gone by the time it is asked, or
/// that refuses the query, is left out; a manager that cannot be read throws
/// [Win32Error].
List<ServiceImage> listServiceImages() {
  const scManagerConnect = 0x0001;
  const scManagerEnumerateService = 0x0004;
  const serviceQueryConfig = 0x0001;
  const scEnumProcessInfo = 0;
  const serviceWin32 = 0x30;
  const serviceStateAll = 3;
  const errorMoreData = 234;
  const errorInsufficientBuffer = 122;
  const errorAccessDenied = 5;
  // ENUM_SERVICE_STATUS_PROCESSW: two pointers and a SERVICE_STATUS_PROCESS
  // (nine DWORDs), padded to 8 bytes.
  const entrySize = 56;

  final manager = callReadingError(
    () => _openScManager(
      nullptr,
      nullptr,
      scManagerConnect | scManagerEnumerateService,
    ),
    (h) => h == 0,
  );
  if (manager.value == 0) throw Win32Error('OpenSCManagerW', manager.error);
  final needed = calloc<Uint32>();
  final returned = calloc<Uint32>();
  final resume = calloc<Uint32>();
  final names = <String>[];
  try {
    var size = 0;
    var buffer = nullptr.cast<Uint8>();
    try {
      while (true) {
        final done = callReadingError(
          () => _enumServicesStatusEx(
            manager.value,
            scEnumProcessInfo,
            serviceWin32,
            serviceStateAll,
            buffer,
            size,
            needed,
            returned,
            resume,
            nullptr,
          ),
          (r) => r == 0,
        );
        final more = done.value == 0 && done.error == errorMoreData;
        if (done.value == 0 && !more) {
          throw Win32Error('EnumServicesStatusExW', done.error);
        }
        for (var i = 0; i < returned.value; i++) {
          final name = (buffer + i * entrySize).cast<Pointer<Utf16>>().value;
          names.add(name.toDartString());
        }
        if (!more) break;
        if (needed.value > size) {
          // The names point into the buffer, and they are copied already.
          if (buffer != nullptr) calloc.free(buffer);
          size = needed.value;
          buffer = calloc<Uint8>(size);
        }
      }
    } finally {
      if (buffer != nullptr) calloc.free(buffer);
    }

    final images = <ServiceImage>[];
    var configSize = 8192;
    var config = calloc<Uint8>(configSize);
    try {
      for (final name in names) {
        final nativeName = name.toNativeUtf16();
        try {
          final service = callReadingError(
            () => _openService(manager.value, nativeName, serviceQueryConfig),
            (h) => h == 0,
          );
          if (service.value == 0) {
            if (service.error == errorServiceDoesNotExist ||
                service.error == errorAccessDenied) {
              continue;
            }
            throw Win32Error('OpenServiceW', service.error);
          }
          try {
            var query = callReadingError(
              () => _queryServiceConfig(
                service.value,
                config,
                configSize,
                needed,
              ),
              (r) => r == 0,
            );
            if (query.value == 0 && query.error == errorInsufficientBuffer) {
              calloc.free(config);
              configSize = needed.value;
              config = calloc<Uint8>(configSize);
              query = callReadingError(
                () => _queryServiceConfig(
                  service.value,
                  config,
                  configSize,
                  needed,
                ),
                (r) => r == 0,
              );
            }
            if (query.value == 0) continue;
            // QUERY_SERVICE_CONFIGW: three DWORDs, then lpBinaryPathName at
            // the next pointer-aligned offset.
            final path = (config + 16).cast<Pointer<Utf16>>().value;
            images.add((
              name: name,
              imagePath: path == nullptr ? '' : path.toDartString(),
            ));
          } finally {
            _closeServiceHandle(service.value);
          }
        } finally {
          calloc.free(nativeName);
        }
      }
    } finally {
      calloc.free(config);
    }
    return images;
  } finally {
    _closeServiceHandle(manager.value);
    calloc
      ..free(needed)
      ..free(returned)
      ..free(resume);
  }
}
