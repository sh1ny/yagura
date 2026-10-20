import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yagura_proto/yagura_proto.dart';

import '../connection.dart';
import '../providers.dart';
import '../transport.dart';

/// Shows a dialog for every prompt pending on a daemon (a Steam Guard code or a
/// mobile approval), whichever device started the operation (design D13).
///
/// It draws nothing itself; keep one per daemon under the app's navigator.
class PromptListener extends ConsumerStatefulWidget {
  const PromptListener({super.key, required this.daemonId});

  final String daemonId;

  @override
  ConsumerState<PromptListener> createState() => _PromptListenerState();
}

class _PromptListenerState extends ConsumerState<PromptListener> {
  /// The route of each prompt's open dialog.
  final _open = <String, BuildContext>{};

  /// Prompts a dialog was shown for and that are still pending.
  final _shown = <String>{};

  /// Prompts the admin hid: they do not open again.
  final _hidden = <String>{};
  StreamSubscription<PromptResolution>? _resolutions;

  @override
  void initState() {
    super.initState();
    ref.listenManual(promptsProvider(widget.daemonId), (_, next) {
      _sync(next.value ?? const []);
    }, fireImmediately: true);
    _resolutions = ref
        .read(daemonConnectionProvider(widget.daemonId))
        .promptResolutions
        .listen(_resolved);
  }

  @override
  void dispose() {
    unawaited(_resolutions?.cancel());
    super.dispose();
  }

  void _sync(List<PendingPrompt> prompts) {
    final ids = {for (final p in prompts) p.prompt.id};
    _hidden.removeWhere((id) => !ids.contains(id));
    for (final id in _shown.toList()) {
      if (ids.contains(id)) continue;
      // Gone without a word from the daemon (a reconnect snapshot, the
      // operation ended): the dialog just closes.
      _shown.remove(id);
      _close(id);
    }
    for (final pending in prompts) {
      final id = pending.prompt.id;
      if (_shown.contains(id) || _hidden.contains(id)) continue;
      _show(pending);
    }
  }

  void _show(PendingPrompt pending) {
    final id = pending.prompt.id;
    _shown.add(id);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          _open[id] = dialogContext;
          return PromptDialog(daemonId: widget.daemonId, initial: pending);
        },
      ).whenComplete(() {
        _open.remove(id);
        // Closed by the admin while the prompt is pending: leave it be.
        if (_shown.contains(id)) _hidden.add(id);
      }),
    );
  }

  void _close(String id) {
    final dialogContext = _open.remove(id);
    if (dialogContext == null || !dialogContext.mounted) return;
    final route = ModalRoute.of(dialogContext);
    if (route != null && route.isActive) {
      Navigator.of(dialogContext).removeRoute(route);
    }
  }

  void _resolved(PromptResolution resolution) {
    final prompt = resolution.prompt.prompt;
    if (!_shown.remove(prompt.id)) return;
    _close(prompt.id);
    if (!mounted) return;
    final account = prompt.steamAccount.isEmpty
        ? 'the Steam account'
        : prompt.steamAccount;
    final message = switch (resolution.resolved.outcome) {
      'answered' => 'The prompt for $account was answered on another device.',
      'expired' => 'The prompt for $account expired.',
      'cancelled' => 'The prompt for $account was cancelled.',
      _ => 'The prompt for $account is closed.',
    };
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// The dialog of one pending prompt: a code entry for `email` and
/// `authenticator`, a notice with the time left for `mobile_approval`.
class PromptDialog extends ConsumerStatefulWidget {
  const PromptDialog({
    super.key,
    required this.daemonId,
    required this.initial,
  });

  final String daemonId;
  final PendingPrompt initial;

  @override
  ConsumerState<PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends ConsumerState<PromptDialog> {
  final _code = TextEditingController();
  Timer? _tick;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    _code.dispose();
    super.dispose();
  }

  PendingPrompt get _pending =>
      ref
          .watch(promptsProvider(widget.daemonId))
          .value
          ?.where((p) => p.prompt.id == widget.initial.prompt.id)
          .firstOrNull ??
      widget.initial;

  /// Runs [call]; a failure stays in the dialog, except a prompt that another
  /// device answered first, which closes with a notice.
  Future<void> _run(Future<void> Function(DaemonConnection c) call) async {
    final connection = ref.read(daemonConnectionProvider(widget.daemonId));
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await call(connection);
      // The prompt leaves the daemon's list, which closes this dialog.
    } on DaemonCallException catch (e) {
      if (e.reason == 'prompt_resolved') {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('The prompt was answered on another device.'),
          ),
        );
      } else if (mounted) {
        setState(() => _error = e.message.isEmpty ? e.reason : e.message);
      }
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submit(PendingPrompt pending) {
    final code = _code.text.trim();
    if (code.isEmpty || _busy) return;
    unawaited(_run((c) => c.respondToPrompt(pending, code)));
  }

  String _timeLeft(Prompt prompt) {
    if (!prompt.hasExpiresAt()) return '';
    final now = ref.read(clockProvider)();
    var left = prompt.expiresAt.toDateTime().difference(now);
    if (left.isNegative) left = Duration.zero;
    final seconds = (left.inSeconds % 60).toString().padLeft(2, '0');
    return '${left.inMinutes}:$seconds left';
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    final prompt = pending.prompt;
    final mobile = prompt.kind == 'mobile_approval';
    final account = prompt.steamAccount.isEmpty
        ? 'the Steam account'
        : prompt.steamAccount;
    final instruction = switch (prompt.kind) {
      'email' => 'Enter the code Steam emailed to the address of $account.',
      'authenticator' =>
        'Enter the code from the Steam Mobile app for $account.',
      'mobile_approval' =>
        'Open the Steam Mobile app and approve the sign-in of $account. '
            'This closes when you do.',
      _ => 'Steam asks for input for $account.',
    };
    final timeLeft = _timeLeft(prompt);
    return AlertDialog(
      key: const ValueKey('prompt:dialog'),
      title: Text(mobile ? 'Approve on your phone' : 'Steam Guard code'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(instruction),
            if (prompt.message.isNotEmpty) Text(prompt.message),
            if (timeLeft.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(timeLeft),
              ),
            if (!mobile)
              TextField(
                key: const ValueKey('prompt:code'),
                controller: _code,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Code'),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(pending),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('prompt:cancel'),
          onPressed: _busy
              ? null
              : () => unawaited(_run((c) => c.cancelPrompt(pending))),
          child: const Text('Cancel operation'),
        ),
        TextButton(
          key: const ValueKey('prompt:hide'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Hide'),
        ),
        if (!mobile)
          FilledButton(
            key: const ValueKey('prompt:submit'),
            onPressed: _busy || _code.text.trim().isEmpty
                ? null
                : () => _submit(pending),
            child: const Text('Submit'),
          ),
      ],
    );
  }
}
