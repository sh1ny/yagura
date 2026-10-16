/// Raw bindings to the quickjs-ng code asset built by `hook/build.dart`.
///
/// Spike surface (task 1.2): enough to evaluate a script and read an int.
/// The full binding arrives with task 2.2.
@DefaultAsset('package:yagura_js/src/quickjs_ffi.dart')
library;

import 'dart:ffi';

final class JSRuntime extends Opaque {}

final class JSContext extends Opaque {}

/// `JSValue` without NaN boxing (64-bit targets): a 64-bit union and a tag.
final class JSValue extends Struct {
  @Int64()
  external int u;

  @Int64()
  external int tag;
}

/// `JS_EVAL_TYPE_GLOBAL`.
const int jsEvalTypeGlobal = 0;

@Native<Pointer<JSRuntime> Function()>(symbol: 'JS_NewRuntime')
external Pointer<JSRuntime> jsNewRuntime();

@Native<Void Function(Pointer<JSRuntime>)>(symbol: 'JS_FreeRuntime')
external void jsFreeRuntime(Pointer<JSRuntime> rt);

@Native<Pointer<JSContext> Function(Pointer<JSRuntime>)>(
  symbol: 'JS_NewContext',
)
external Pointer<JSContext> jsNewContext(Pointer<JSRuntime> rt);

@Native<Void Function(Pointer<JSContext>)>(symbol: 'JS_FreeContext')
external void jsFreeContext(Pointer<JSContext> ctx);

@Native<
  JSValue Function(Pointer<JSContext>, Pointer<Char>, Size, Pointer<Char>, Int)
>(symbol: 'JS_Eval')
external JSValue jsEval(
  Pointer<JSContext> ctx,
  Pointer<Char> input,
  int inputLength,
  Pointer<Char> filename,
  int evalFlags,
);

@Native<Int Function(Pointer<JSContext>, Pointer<Int32>, JSValue)>(
  symbol: 'JS_ToInt32',
)
external int jsToInt32(
  Pointer<JSContext> ctx,
  Pointer<Int32> result,
  JSValue v,
);

@Native<Void Function(Pointer<JSContext>, JSValue)>(symbol: 'JS_FreeValue')
external void jsFreeValue(Pointer<JSContext> ctx, JSValue v);
