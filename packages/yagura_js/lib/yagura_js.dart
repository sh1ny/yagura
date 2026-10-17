/// quickjs-ng bindings over FFI for plugin hooks.
///
/// [QuickJsRuntime] owns one QuickJS runtime and one context, enforces a heap
/// limit, a stack limit and a monotonic deadline, and exchanges only JSON with
/// the script. Use it from a single isolate.
library;

export 'src/quickjs.dart';
