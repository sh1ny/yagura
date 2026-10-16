import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';
import 'package:yagura_js/src/quickjs_ffi.dart';

void main() {
  test('evaluates 1+1 through FFI', () {
    final rt = jsNewRuntime();
    final ctx = jsNewContext(rt);
    final source = '1+1'.toNativeUtf8();
    final filename = '<smoke>'.toNativeUtf8();
    final out = calloc<Int32>();
    try {
      final value = jsEval(
        ctx,
        source.cast(),
        source.length,
        filename.cast(),
        jsEvalTypeGlobal,
      );
      expect(jsToInt32(ctx, out, value), 0);
      jsFreeValue(ctx, value);
      expect(out.value, 2);
    } finally {
      calloc.free(out);
      calloc.free(source);
      calloc.free(filename);
      jsFreeContext(ctx);
      jsFreeRuntime(rt);
    }
  });
}
