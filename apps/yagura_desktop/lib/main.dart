import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'src/ui/daemons_page.dart';

void main() {
  runApp(const YaguraApp());
}

/// The desktop client: the paired daemons, one connection each (design D13).
class YaguraApp extends StatelessWidget {
  const YaguraApp({super.key, this.overrides = const []});

  /// Provider overrides (tests inject fake daemons, keychain and clock).
  final List<Override> overrides;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        title: 'Yagura',
        theme: ThemeData(colorSchemeSeed: Colors.indigo),
        home: const DaemonsPage(),
      ),
    );
  }
}
