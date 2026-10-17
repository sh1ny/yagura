import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection.dart';
import '../providers.dart';

/// Shows the daemon's connection state.
class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key, required this.daemonId});

  final String daemonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status =
        ref.watch(connectionStatusProvider(daemonId)).value ??
        const Connecting();
    final scheme = Theme.of(context).colorScheme;
    final (icon, text, color) = switch (status) {
      Connecting() => (Icons.sync, 'Connecting…', scheme.secondaryContainer),
      Connected(:final info, :final negotiated) => (
        Icons.check_circle_outline,
        'Connected to ${info.hostName.isEmpty ? 'daemon' : info.hostName}'
            ' · API ${negotiated.effective}',
        scheme.primaryContainer,
      ),
      Reconnecting() => (
        Icons.sync_problem,
        'Reconnecting…',
        scheme.tertiaryContainer,
      ),
      IncompatibleDaemon(:final client, :final daemon) => (
        Icons.block,
        'Incompatible: client API $client, daemon API '
            '${daemon.join(', ')}',
        scheme.errorContainer,
      ),
    };
    return Material(
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
