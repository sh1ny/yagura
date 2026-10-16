import 'package:flutter/material.dart';

void main() {
  runApp(const YaguraApp());
}

/// Placeholder shell until the desktop client skeleton (task 9.3).
class YaguraApp extends StatelessWidget {
  const YaguraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Yagura',
      home: Scaffold(body: Center(child: Text('Yagura'))),
    );
  }
}
