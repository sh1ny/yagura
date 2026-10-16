# yagura_js

quickjs-ng bindings over FFI for plugin hooks (ADR 0003).

## Native build

`hook/build.dart` compiles the vendored quickjs-ng amalgam with `native_toolchain_c` into the `quickjs` code asset whenever a package that depends on `yagura_js` runs `dart test`, `dart run` or `dart build`. quickjs-libc is not built (no `QJS_BUILD_LIBC`): hooks get only the host API Yagura registers.

| Target | Compiler | Flags (from quickjs-ng's CMakeLists.txt) |
|---|---|---|
| Windows x64 | MSVC `cl.exe` (found through `vswhere`) | `/std:c11 /experimental:c11atomics /J` and its warning suppressions |
| Linux x64 | clang | `-std=gnu11 -funsigned-char -fvisibility=hidden`, linked with `m` and `pthread` |

Only `JS_EXTERN` symbols are exported (`BUILDING_QJS_SHARED`).

## Vendored source

`third_party/quickjs-ng/`: `quickjs-amalgam.c` and `quickjs.h` from the `quickjs-amalgam.zip` asset of quickjs-ng [v0.17.0](https://github.com/quickjs-ng/quickjs/releases/tag/v0.17.0) (zip SHA-256 `a0955463c74809173a253ff87365095e6972e8b171cfb6aa8a1e781adf35cfeb`), with its MIT `LICENSE`. Upgrades are deliberate: replace both files and the license, update the tag and hash here, and re-run the tests on Windows and Linux.

## Spike 1.2 outcome (M1, ADR 0003)

MSVC works; no clang-cl fallback was needed. The amalgam compiles as C11 with `/experimental:c11atomics` and the smoke test (`test/smoke_test.dart`, `1+1` through FFI) passes:

- Windows CI runner (`windows-latest`): MSVC 19.51.36260 x64, CI run 38975924413.
- Linux CI runner (`ubuntu-latest`): clang 18, same run. Strict `-std=c11` failed there (17 errors: `clock_gettime`, `alloca`, `localtime_r` and other POSIX names are hidden), so Linux builds with `gnu11`, quickjs-ng's own CMake default.
- Locally: MSVC 19.51 (Visual Studio 2026) on Windows 11.

The quickjs-ng API is used directly through `@Native` bindings on its `JS_EXTERN` functions (`JSValue` is passed by value as a 16-byte struct); macros and `static inline` helpers in `quickjs.h` are not exported.

## API

`package:yagura_js/yagura_js.dart` exposes `QuickJsRuntime`, one quickjs-ng runtime with one context, used from a single isolate. Values cross the boundary only as JSON.

```dart
final js = QuickJsRuntime(); // 64 MiB heap, 512 KiB script stack by default
js.setDeadline(const Duration(seconds: 5)); // monotonic; scripts cannot catch it
js.registerHostFunction('yagura.log', (args) => null); // dotted path, JSON args
js.hideHostBridge();
js.eval('function f(x) { return {x}; }', filename: 'hooks.js');
final result = js.callFunction('f', [1]); // {x: 1}
js.dispose();
```

- `eval` and `callFunction` return the completion value converted through JSON (`undefined` becomes `null`).
- A script exception becomes a `JsException` with `name`, `message`, `stack` (`file:line:column`) and the error's string `code`; `isOutOfMemory` is true when the heap limit was hit. A deadline stop is a `JsInterruptedException`.
- A host function throws `HostException(code, message)` to raise a JavaScript `Error` with that `code`; any other Dart error becomes code `internal_error`.
- The default script stack is 512 KiB, not the 1 MiB of design D4: Dart isolate threads on Windows have 1 MiB of stack in total, and a 1 MiB script limit overran it (access violations).
