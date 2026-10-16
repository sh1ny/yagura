# 0003. Hooks run in quickjs-ng through an in-repo FFI binding, one disposable runtime per call

- Status: accepted
- Date: 2026-10-16
- Supersedes: —

## Context
Hooks are short JavaScript functions that manipulate strings, JSON and config text. They must never stall the daemon or eat unbounded memory, and a bad hook must fail visibly. The existing pub.dev bindings were checked on 2026-10-16: `quickjs_runtime` 0.3.6 builds only a Linux `.so` with gcc, vendors QuickJS 2024-01-13, and documents no interrupt handler or memory limit; `flutter_js`/`flutter_qjs` require Flutter. Dart build hooks (Dart 3.10+) with `native_toolchain_c` can compile C sources as part of `dart build`.

## Decision
Garrison ships `packages/garrison_js`: a thin `dart:ffi` binding to vendored quickjs-ng, compiled by a build hook for each target (MSVC on Windows, clang/gcc on Linux). It exposes only what hooks need: create runtime and context, set memory limit and max stack size, set an interrupt handler, evaluate, call a function with JSON in and JSON out, and register synchronous host functions with JSON arguments. Each hook call runs in a dedicated worker isolate with a fresh runtime that is freed after the call. The interrupt handler enforces the hook's deadline from inside the engine; the memory limit caps the heap. Host functions are synchronous Dart functions in that worker isolate, bounded in input size, and side-effect free except logging: they read files inside the instance (read-only), list files, and parse or serialise config text. Hooks never write files: they return file edits (`{files: [{path, format, patch|content}]}`) in their result, and the config binder applies them atomically and records their hashes (ADR 0004). Long work (copying, downloads) is a daemon step, never a host function. At most 4 hook workers run at once per host.

**Rejected: `quickjs_runtime` from pub.dev.** No Windows build path, no interrupt or memory limit, single unverified maintainer; the deadline would have to be an `Isolate.kill`, which cannot stop native code.

**Rejected: Lua via a pure-Dart VM (`lua_dardo_plus`).** No native libraries to build, but no regex or JSON, which are most of what hooks do.

**Reversal cost: medium.** The hook contract (JSON in, JSON out, a fixed host API) is engine-independent; swapping the engine rewrites `garrison_js` only.

## Consequences
- Garrison owns a small C build and an FFI surface; quickjs-ng upgrades are deliberate.
- Hooks cannot be async in v1 (no event loop); host functions are synchronous and bounded.
- An early spike must prove the build hook produces a working library on Windows with MSVC (roadmap M1).
