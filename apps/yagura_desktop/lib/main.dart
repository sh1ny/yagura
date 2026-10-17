import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'src/providers.dart';
import 'src/ui/home_page.dart';

void main() {
  runApp(const YaguraApp());
}

/// The desktop client: one dev-mode daemon connection (design D10).
class YaguraApp extends StatelessWidget {
  const YaguraApp({super.key, this.overrides = const []});

  /// Provider overrides (tests inject a connection over a fake transport).
  final List<Override> overrides;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        title: 'Yagura',
        theme: ThemeData(colorSchemeSeed: Colors.indigo),
        home: const HomePage(daemonId: kDevDaemonId),
      ),
    );
  }
}
