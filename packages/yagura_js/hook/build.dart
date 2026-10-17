import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Compiles the vendored quickjs-ng amalgam (without quickjs-libc) into the
/// `quickjs` code asset: MSVC on Windows, clang on Linux. Flags follow
/// quickjs-ng's own CMakeLists.txt.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final windows = input.config.code.targetOS == OS.windows;
    await CBuilder.library(
      name: 'quickjs',
      assetName: 'src/quickjs_ffi.dart',
      sources: ['third_party/quickjs-ng/quickjs-amalgam.c'],
      includes: ['third_party/quickjs-ng'],
      // quickjs-ng builds as C11 with extensions (CMake's default gnu11);
      // strict c11 hides the POSIX clock, alloca and localtime_r it uses.
      std: windows ? 'c11' : 'gnu11',
      defines: {'QUICKJS_NG_BUILD': null, 'BUILDING_QJS_SHARED': null},
      flags: windows
          ? [
              '/experimental:c11atomics',
              '/J', // char is unsigned, like -funsigned-char
              '/wd4018', '/wd4061', '/wd4100', '/wd4200', '/wd4242',
              '/wd4244', '/wd4245', '/wd4267', '/wd4388', '/wd4389',
              '/wd4456', '/wd4457', '/wd4710', '/wd4711', '/wd4820',
              '/wd4996', '/wd5045',
            ]
          : ['-funsigned-char', '-fvisibility=hidden'],
      libraries: windows ? const [] : ['m', 'pthread'],
    ).run(input: input, output: output);
  });
}
