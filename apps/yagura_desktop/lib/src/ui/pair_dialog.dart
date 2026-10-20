import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pairing.dart';
import '../providers.dart';

/// Asks for a pairing string and a device name and pairs the daemon.
///
/// Opens over the daemon list; pops with `true` once the daemon is added.
Future<bool> showPairDialog(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => const PairDialog(),
    ) ??
    false;

class PairDialog extends ConsumerStatefulWidget {
  const PairDialog({super.key});

  @override
  ConsumerState<PairDialog> createState() => _PairDialogState();
}

class _PairDialogState extends ConsumerState<PairDialog> {
  final _string = TextEditingController();
  final _name = TextEditingController(text: _defaultName());
  bool _busy = false;
  String? _error;

  static String _defaultName() {
    try {
      return Platform.localHostname;
    } on Object {
      return '';
    }
  }

  @override
  void dispose() {
    _string.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(daemonRegistryProvider.notifier)
          .pair(_string.text, _name.text);
      if (mounted) Navigator.pop(context, true);
    } on PairingFailure catch (e) {
      if (mounted) setState(() => _error = '${e.reason}: ${e.message}');
    } on Object catch (e) {
      // Nothing else should get here; whatever does is shown, not swallowed.
      if (mounted) setState(() => _error = 'pairing_failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final refused =
        ref.watch(daemonListProblemProvider)?.savingRefused ?? false;
    final ready =
        !refused &&
        _string.text.trim().isNotEmpty &&
        _name.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Pair a daemon'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'On the host, run "yagurad pair" as an administrator and paste '
              'the line it prints. The code works once, for ten minutes.',
            ),
            const SizedBox(height: 12),
            if (refused)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Pairing is not possible while the daemon list cannot be '
                  'saved. See the notice on the daemon list.',
                  key: const ValueKey('pair:refused'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            TextField(
              key: const ValueKey('pair:string'),
              controller: _string,
              enabled: !_busy,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Pairing string',
                hintText: 'yagura://host:7443?code=…&ca=sha256:…',
              ),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              key: const ValueKey('pair:name'),
              controller: _name,
              enabled: !_busy,
              maxLength: 64,
              decoration: const InputDecoration(
                labelText: 'Name of this device',
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  key: const ValueKey('pair:error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('pair:submit'),
          onPressed: ready && !_busy ? _submit : null,
          child: const Text('Pair'),
        ),
      ],
    );
  }
}
