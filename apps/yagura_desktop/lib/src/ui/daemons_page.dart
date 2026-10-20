import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection.dart';
import '../daemon_record.dart';
import '../providers.dart';
import 'home_page.dart';
import 'instance_list.dart' show instanceStateLabel;
import 'pair_dialog.dart';
import 'prompt_dialog.dart';

/// The word the list shows for a connection state (design D13).
String daemonStateLabel(ConnectionStatus status) => switch (status) {
  Connecting() || Reconnecting() => 'connecting',
  Connected() => 'connected',
  Offline() => 'offline',
  IncompatibleDaemon() => 'incompatible',
  Revoked() => 'revoked',
  Expired() => 'expired',
};

String _time(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// One sentence about the state: the last error and when the daemon was last
/// seen, or what the admin has to do.
String daemonStateDetail(ConnectionStatus status) => switch (status) {
  Connecting() => 'Connecting…',
  Reconnecting() => 'Connection lost. Reconnecting…',
  Connected(:final info, :final negotiated) =>
    'Connected to ${info.hostName.isEmpty ? 'daemon' : info.hostName}'
        ' · API ${negotiated.effective}',
  Offline(:final error, :final lastSeen) =>
    '$error · ${lastSeen == null ? 'Not reached since the client started' : 'Last seen ${_time(lastSeen)}'}',
  IncompatibleDaemon(:final client, :final daemon) =>
    'Incompatible: client API $client, daemon API ${daemon.join(', ')}',
  Revoked() => 'This device was revoked by the daemon. Pair again to continue.',
  Expired() =>
    'The device certificate expired or its renewal was refused. '
        'Pair again to continue.',
};

/// Added to a daemon's detail line when a certificate it just issued is
/// already due for renewal.
const kClockSuspectNote =
    "The daemon's clock may be wrong: the certificate it just issued is "
    'already due for renewal.';

/// Whether pairing again would fix [status].
bool offersRepair(ConnectionStatus status) => switch (status) {
  Revoked() || Expired() => true,
  Offline(:final error) =>
    error == 'server_ca_mismatch' || error == 'credentials_missing',
  _ => false,
};

/// The paired daemons with their states and instances (design D13).
class DaemonsPage extends ConsumerWidget {
  const DaemonsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daemons = ref.watch(daemonRegistryProvider);
    final problem = ref.watch(daemonListProblemProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yagura'),
        actions: [
          IconButton(
            key: const ValueKey('action:pair'),
            tooltip: 'Pair a daemon',
            icon: const Icon(Icons.add_link),
            onPressed: () => showPairDialog(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          // A Steam Guard prompt of any daemon opens its dialog from here.
          for (final daemon in daemons) PromptListener(daemonId: daemon.id),
          ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (problem != null)
                Card(
                  key: const ValueKey('daemons:problem'),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(problem.message),
                        if (problem.canDiscard)
                          TextButton(
                            key: const ValueKey('daemons:discard'),
                            onPressed: () => _confirmDiscard(
                              context,
                              ref,
                              problem.discardDetail,
                            ),
                            child: const Text('Discard unreadable entries'),
                          ),
                        if (problem.canDiscardCopy)
                          TextButton(
                            key: const ValueKey('daemons:discard-copy'),
                            onPressed: () => _confirmDiscardCopy(context, ref),
                            child: const Text('Discard the damaged copy'),
                          ),
                      ],
                    ),
                  ),
                ),
              if (daemons.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No daemons yet. Pair one with the pairing string that '
                    '"yagurad pair" prints on the host.',
                  ),
                ),
              for (final daemon in daemons)
                _DaemonCard(key: ValueKey('daemon:${daemon.id}'), daemon),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmDiscard(
  BuildContext context,
  WidgetRef ref,
  String detail,
) => _confirmAndRun(
  context,
  title: 'Discard unreadable entries?',
  content: detail,
  confirmKey: const ValueKey('discard:confirm'),
  run: ref.read(daemonRegistryProvider.notifier).discardUnreadable,
  failure: 'The entries were not discarded',
);

Future<void> _confirmDiscardCopy(BuildContext context, WidgetRef ref) =>
    _confirmAndRun(
      context,
      title: 'Discard the damaged copy?',
      content:
          'daemons.json.damaged, the copy kept of the damaged daemon list, is '
          'deleted for good. Afterwards the keys and certificates stored in '
          'the keychain for daemons that are not in the current list are '
          'deleted too. To keep them, restore the copy by hand first.',
      confirmKey: const ValueKey('discard-copy:confirm'),
      run: ref.read(daemonRegistryProvider.notifier).discardDamagedCopy,
      failure: 'The copy was not discarded',
    );

Future<void> _confirmAndRun(
  BuildContext context, {
  required String title,
  required String content,
  required Key confirmKey,
  required Future<void> Function() run,
  required String failure,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(content)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: confirmKey,
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await run();
  } on Object catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('$failure: $e')));
    }
  }
}

class _DaemonCard extends ConsumerWidget {
  const _DaemonCard(this.daemon, {super.key});

  final DaemonRecord daemon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = daemon.id;
    final status =
        ref.watch(connectionStatusProvider(id)).value ?? const Connecting();
    final instances = ref.watch(instancesProvider(id)).value ?? const [];
    final clockSuspect = ref.watch(daemonClockSuspectProvider).contains(id);
    final scheme = Theme.of(context).colorScheme;
    final problem = switch (status) {
      Offline() || Revoked() || Expired() || IncompatibleDaemon() => true,
      _ => false,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        daemon.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(daemon.address),
                    ],
                  ),
                ),
                Chip(
                  backgroundColor: problem
                      ? scheme.errorContainer
                      : scheme.secondaryContainer,
                  label: Text(
                    daemonStateLabel(status),
                    key: ValueKey('daemon:$id:state'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              clockSuspect
                  ? '${daemonStateDetail(status)} $kClockSuspectNote'
                  : daemonStateDetail(status),
              key: ValueKey('daemon:$id:detail'),
              style: TextStyle(color: problem ? scheme.error : null),
            ),
            for (final instance in instances)
              ListTile(
                key: ValueKey('daemon:$id:instance:${instance.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(instance.name),
                trailing: Text(instanceStateLabel(instance.state)),
              ),
            OverflowBar(
              alignment: MainAxisAlignment.start,
              children: [
                if (status is Connected)
                  TextButton(
                    key: ValueKey('daemon:$id:open'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => HomePage(daemonId: id),
                      ),
                    ),
                    child: const Text('Manage'),
                  ),
                if (offersRepair(status))
                  TextButton(
                    key: ValueKey('daemon:$id:repair'),
                    onPressed: () => showPairDialog(context),
                    child: const Text('Pair again'),
                  ),
                if (!daemon.isDev)
                  TextButton(
                    key: ValueKey('daemon:$id:remove'),
                    onPressed: () => _confirmRemove(context, ref),
                    child: const Text('Remove'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${daemon.name}?'),
        content: const Text(
          'This device forgets the daemon and deletes its key and certificate '
          'from the keychain. The daemon keeps listing the device until an '
          'administrator revokes it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('remove:confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove != true) return;
    try {
      await ref.read(daemonRegistryProvider.notifier).remove(daemon.id);
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('${daemon.name} was not removed: $e')),
        );
      }
    }
  }
}
