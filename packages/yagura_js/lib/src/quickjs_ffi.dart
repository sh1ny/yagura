/// Raw bindings to the quickjs-ng code asset built by `hook/build.dart`.
///
/// Only `JS_EXTERN` functions are bound: quickjs-ng does not export the
/// macros and `static inline` helpers of `quickjs.h`, so the few that are
/// needed (value tags, `JS_NewCFunction`) are reimplemented in `quickjs.dart`.
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

/// `JS_CFUNC_generic` of `JSCFunctionEnum`.
const int jsCFuncGeneric = 0;

// Value tags (`JS_TAG_*`).
const int jsTagString = -7;
const int jsTagStringRope = -6;
const int jsTagObject = -1;
const int jsTagUndefined = 3;
const int jsTagException = 6;

/// `JSCFunction`: `JSValue f(JSContext*, JSValueConst this, int argc,
/// JSValueConst* argv)`.
typedef JSCFunctionNative = JSValue Function(
  Pointer<JSContext>,
  JSValue,
  Int,
  Pointer<JSValue>,
);

/// `JSInterruptHandler`: `int f(JSRuntime*, void* opaque)`.
typedef JSInterruptHandlerNative = Int Function(
  Pointer<JSRuntime>,
  Pointer<Void>,
);

@Native<Pointer<JSRuntime> Function()>(symbol: 'JS_NewRuntime')
external Pointer<JSRuntime> jsNewRuntime();

@Native<Void Function(Pointer<JSRuntime>)>(symbol: 'JS_FreeRuntime')
external void jsFreeRuntime(Pointer<JSRuntime> rt);

@Native<Void Function(Pointer<JSRuntime>, Size)>(symbol: 'JS_SetMemoryLimit')
external void jsSetMemoryLimit(Pointer<JSRuntime> rt, int limit);

@Native<Void Function(Pointer<JSRuntime>, Size)>(symbol: 'JS_SetMaxStackSize')
external void jsSetMaxStackSize(Pointer<JSRuntime> rt, int stackSize);

@Native<Void Function(Pointer<JSRuntime>)>(symbol: 'JS_UpdateStackTop')
external void jsUpdateStackTop(Pointer<JSRuntime> rt);

@Native<
  Void Function(
    Pointer<JSRuntime>,
    Pointer<NativeFunction<JSInterruptHandlerNative>>,
    Pointer<Void>,
  )
>(symbol: 'JS_SetInterruptHandler')
external void jsSetInterruptHandler(
  Pointer<JSRuntime> rt,
  Pointer<NativeFunction<JSInterruptHandlerNative>> handler,
  Pointer<Void> opaque,
);

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

@Native<JSValue Function(Pointer<JSContext>)>(symbol: 'JS_GetException')
external JSValue jsGetException(Pointer<JSContext> ctx);

@Native<JSValue Function(Pointer<JSContext>)>(symbol: 'JS_GetGlobalObject')
external JSValue jsGetGlobalObject(Pointer<JSContext> ctx);

@Native<Bool Function(Pointer<JSContext>, JSValue)>(symbol: 'JS_IsFunction')
external bool jsIsFunction(Pointer<JSContext> ctx, JSValue v);

@Native<JSValue Function(Pointer<JSContext>, JSValue, Pointer<Char>)>(
  symbol: 'JS_GetPropertyStr',
)
external JSValue jsGetPropertyStr(
  Pointer<JSContext> ctx,
  JSValue obj,
  Pointer<Char> name,
);

/// Takes ownership of [value].
@Native<Int Function(Pointer<JSContext>, JSValue, Pointer<Char>, JSValue)>(
  symbol: 'JS_SetPropertyStr',
)
external int jsSetPropertyStr(
  Pointer<JSContext> ctx,
  JSValue obj,
  Pointer<Char> name,
  JSValue value,
);

@Native<
  JSValue Function(Pointer<JSContext>, JSValue, JSValue, Int, Pointer<JSValue>)
>(symbol: 'JS_Call')
external JSValue jsCall(
  Pointer<JSContext> ctx,
  JSValue func,
  JSValue thisValue,
  int argc,
  Pointer<JSValue> argv,
);

@Native<
  JSValue Function(Pointer<JSContext>, Pointer<Char>, Size, Pointer<Char>)
>(symbol: 'JS_ParseJSON')
external JSValue jsParseJSON(
  Pointer<JSContext> ctx,
  Pointer<Char> buf,
  int bufLength,
  Pointer<Char> filename,
);

@Native<JSValue Function(Pointer<JSContext>, JSValue, JSValue, JSValue)>(
  symbol: 'JS_JSONStringify',
)
external JSValue jsJSONStringify(
  Pointer<JSContext> ctx,
  JSValue obj,
  JSValue replacer,
  JSValue space,
);

@Native<JSValue Function(Pointer<JSContext>, Pointer<Char>, Size)>(
  symbol: 'JS_NewStringLen',
)
external JSValue jsNewStringLen(
  Pointer<JSContext> ctx,
  Pointer<Char> str,
  int length,
);

@Native<
  Pointer<Char> Function(Pointer<JSContext>, Pointer<Size>, JSValue, Bool)
>(symbol: 'JS_ToCStringLen2')
external Pointer<Char> jsToCStringLen2(
  Pointer<JSContext> ctx,
  Pointer<Size> length,
  JSValue value,
  bool cesu8,
);

@Native<Void Function(Pointer<JSContext>, Pointer<Char>)>(
  symbol: 'JS_FreeCString',
)
external void jsFreeCString(Pointer<JSContext> ctx, Pointer<Char> str);

@Native<
  JSValue Function(
    Pointer<JSContext>,
    Pointer<NativeFunction<JSCFunctionNative>>,
    Pointer<Char>,
    Int,
    Int,
    Int,
  )
>(symbol: 'JS_NewCFunction2')
external JSValue jsNewCFunction2(
  Pointer<JSContext> ctx,
  Pointer<NativeFunction<JSCFunctionNative>> func,
  Pointer<Char> name,
  int length,
  int cproto,
  int magic,
);
