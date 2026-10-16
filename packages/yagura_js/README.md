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
