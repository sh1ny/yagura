import 'package:test/test.dart';
import 'package:yagura_js/yagura_js.dart';

void main() {
  late QuickJsRuntime js;

  setUp(() => js = QuickJsRuntime());
  tearDown(() => js.dispose());

  group('eval and call', () {
    test('returns JSON-compatible values', () {
      expect(js.eval('1 + 1'), 2);
      expect(js.eval('({a: [1, "x", null, true], b: {c: 2.5}})'), {
        'a': [1, 'x', null, true],
        'b': {'c': 2.5},
      });
      expect(js.eval('undefined'), isNull);
      expect(js.eval('"héllo \u{1F600}"'), 'héllo \u{1F600}');
    });

    test('calls a global function with JSON arguments', () {
      js.eval('function add(a, o) { return {sum: a + o.n, echo: o}; }');
      expect(
        js.callFunction('add', [
          2,
          {'n': 40},
        ]),
        {
          'sum': 42,
          'echo': {'n': 40},
        },
      );
    });

    test('a throwing global accessor surfaces its own exception', () {
      js.eval(
        "Object.defineProperty(globalThis, 'boom', "
        "{get() { throw new RangeError('accessor failed'); }})",
      );
      expect(
        () => js.callFunction('boom'),
        throwsA(
          isA<JsException>()
              .having((e) => e.name, 'name', 'RangeError')
              .having((e) => e.message, 'message', 'accessor failed'),
        ),
      );
    });

    test('calling a missing function fails', () {
      expect(() => js.callFunction('nope'), throwsA(isA<JsException>()));
    });
  });

  group('interrupt deadline', () {
    test('stops an infinite loop at the deadline', () {
      js.setDeadline(const Duration(milliseconds: 150));
      final watch = Stopwatch()..start();
      expect(
        () => js.eval('while (true) {}'),
        throwsA(isA<JsInterruptedException>()),
      );
      expect(watch.elapsedMilliseconds, inInclusiveRange(100, 2000));
    });

    test('cannot be swallowed by a script', () {
      js.setDeadline(const Duration(milliseconds: 100));
      expect(
        () => js.eval('try { while (true) {} } catch (e) { "caught" }'),
        throwsA(isA<JsInterruptedException>()),
      );
    });

    test('does not fire before the deadline', () {
      js.setDeadline(const Duration(seconds: 30));
      expect(
        js.eval('let n = 0; for (let i = 0; i < 1e5; i++) n += i; n'),
        isNotNull,
      );
    });
  });

  group('memory limit', () {
    test('fails a runaway allocation without crashing the process', () {
      final small = QuickJsRuntime(memoryLimitBytes: 64 * 1024 * 1024);
      addTearDown(small.dispose);
      expect(
        () => small.eval("'x'.repeat(200 * 1024 * 1024)"),
        throwsA(
          isA<JsException>().having(
            (e) => e.isOutOfMemory,
            'isOutOfMemory',
            true,
          ),
        ),
      );
      // The runtime stays usable below the limit.
      expect(small.eval('1 + 2'), 3);
    });

    test('fails an array that grows past the limit', () {
      expect(
        () => js.eval('const a = []; while (true) a.push({x: 1, y: "z"});'),
        throwsA(
          isA<JsException>().having(
            (e) => e.isOutOfMemory,
            'isOutOfMemory',
            true,
          ),
        ),
      );
    });
  });

  group('native allocation failures', () {
    test('a memory limit too small for a context is a catchable error', () {
      expect(
        () => QuickJsRuntime(memoryLimitBytes: 1),
        throwsA(
          isA<JsException>().having(
            (e) => e.isOutOfMemory,
            'isOutOfMemory',
            true,
          ),
        ),
      );
    });

    test('a failed string conversion is out of memory, not empty text', () {
      final small = QuickJsRuntime(memoryLimitBytes: 16 * 1024 * 1024);
      addTearDown(small.dispose);
      // The 5.5 MiB Latin-1 string fits the heap; its UTF-8 copy does not.
      expect(
        () => small.eval("throw '\u00e9'.repeat(5.5 * 1024 * 1024)"),
        throwsA(
          isA<JsException>().having(
            (e) => e.isOutOfMemory,
            'isOutOfMemory',
            true,
          ),
        ),
      );
      expect(small.eval('1 + 2'), 3);
    });
  });

  group('stack limit', () {
    test('turns unbounded recursion into a catchable error', () {
      expect(
        () => js.eval('function r() { return r() + 1; } r()'),
        throwsA(
          isA<JsException>().having(
            (e) => e.message,
            'message',
            contains('stack'),
          ),
        ),
      );
    });
  });

  group('exception extraction', () {
    test('reports name, message and stack with file and line', () {
      js.eval(
        '\n\nfunction boom() {\n  throw new Error("missing cfg");\n}',
        filename: 'hooks.js',
      );
      try {
        js.callFunction('boom');
        fail('expected a JsException');
      } on JsException catch (e) {
        expect(e.name, 'Error');
        expect(e.message, 'missing cfg');
        expect(e.stack, contains('hooks.js:4'));
      }
    });

    test('reports a syntax error with its line', () {
      try {
        js.eval('var a = 1;\nvar b = ;\n', filename: 'hooks.js');
        fail('expected a JsException');
      } on JsException catch (e) {
        expect(e.name, 'SyntaxError');
        expect('${e.message}\n${e.stack}', contains('hooks.js:2'));
      }
    });

    test('reports a thrown non-error value', () {
      try {
        js.eval('throw "plain"');
        fail('expected a JsException');
      } on JsException catch (e) {
        expect(e.message, 'plain');
      }
    });

    test('keeps the code property of an error', () {
      try {
        js.eval('const e = new Error("m"); e.code = "some_code"; throw e;');
        fail('expected a JsException');
      } on JsException catch (e) {
        expect(e.code, 'some_code');
      }
    });
  });

  group('host functions', () {
    test('receive JSON arguments and return JSON', () {
      js.registerHostFunction('host.math.add', (args) {
        final [a as int, b as int] = args;
        return {'sum': a + b};
      });
      expect(js.eval('host.math.add(2, 3)'), {'sum': 5});
    });

    test('undefined results and null arguments pass through', () {
      js.registerHostFunction('noop', (args) => null);
      expect(js.eval('noop(null) === null'), true);
    });

    test('a HostException surfaces as a JS error with a code', () {
      js.registerHostFunction('fail', (args) {
        throw HostException('sandbox_violation', 'nope');
      });
      expect(
        js.eval('try { fail(); "no" } catch (e) { [e.code, e.message] }'),
        ['sandbox_violation', 'nope'],
      );
    });

    test('another Dart error becomes an internal_error', () {
      js.registerHostFunction('crash', (args) => throw StateError('bad'));
      expect(js.eval('try { crash() } catch (e) { e.code }'), 'internal_error');
    });

    test('the raw bridge is not visible after hiding it', () {
      js.registerHostFunction('x', (args) => 1);
      js.hideHostBridge();
      expect(js.eval('typeof __yagura_host'), 'undefined');
      expect(js.eval('x()'), 1);
    });
  });

  test('dispose is idempotent and later use fails', () {
    final r = QuickJsRuntime();
    r.dispose();
    r.dispose();
    expect(() => r.eval('1'), throwsStateError);
  });
}
