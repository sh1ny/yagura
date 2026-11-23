import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yagura_proto/yagura_proto.dart';

import '../connection.dart';
import '../providers.dart';
import '../transport.dart';

String steamAccountStatusLabel(String status) => switch (status) {
  'ready' => 'ready',
  'reauth_required' => 'needs re-login',
  'adding' => 'adding',
  _ => status.isEmpty ? 'unknown' : status,
};

String _reason(DaemonCallException e) =>
    e.message.isEmpty ? e.reason : e.message;

/// Operations that log an account in or out of a state.
bool _isAccountOperation(OperationState o) =>
    o.kind == 'add_steam_account' || o.kind == 'reauth_steam_account';

/// A daemon's Steam accounts with status and users, and the actions on them.
class SteamAccountsView extends ConsumerStatefulWidget {
  const SteamAccountsView({super.key, required this.daemonId});

  final String daemonId;

  @override
  ConsumerState<SteamAccountsView> createState() => _SteamAccountsViewState();
}

class _SteamAccountsViewState extends ConsumerState<SteamAccountsView> {
  List<SteamAccount>? _accounts;
  String? _loadError;

  /// Why an account was not removed, by account id.
  final _refusals = <String, String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final connection = ref.read(daemonConnectionProvider(widget.daemonId));
    try {
      final transport = await connection.whenConnected();
      final accounts = await transport.listAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _loadError = null;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e is DaemonCallException ? _reason(e) : '$e');
    }
  }

  Future<void> _remove(SteamAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${account.username}?'),
        content: const Text(
          'Its SteamCMD installation and the remembered password are deleted '
          'from the daemon host.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('steam:remove:confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final connection = ref.read(daemonConnectionProvider(widget.daemonId));
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final left = await connection.transport.removeAccount(account.id);
      if (!mounted) return;
      setState(() {
        _accounts = left;
        _refusals.remove(account.id);
      });
    } on DaemonCallException catch (e) {
      if (!mounted) return;
      if (e.reason == 'account_in_use') {
        setState(() => _refusals[account.id] = _reason(e));
      } else {
        messenger?.showSnackBar(SnackBar(content: Text(_reason(e))));
      }
    } on StateError catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _reauth(SteamAccount account) => showDialog<void>(
    context: context,
    builder: (_) => _ReauthDialog(daemonId: widget.daemonId, account: account),
  ).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    // An account operation that ends changes the list (adding -> ready).
    ref.listen(operationsProvider(widget.daemonId), (previous, next) {
      final before = {
        for (final o in previous?.value ?? const <OperationState>[])
          if (o.ended) o.id,
      };
      final ended = (next.value ?? const <OperationState>[]).any(
        (o) => _isAccountOperation(o) && o.ended && !before.contains(o.id),
      );
      if (ended) unawaited(_load());
    });
    final names = {
      for (final i
          in ref.watch(instancesProvider(widget.daemonId)).value ??
              const <Instance>[])
        i.id: i.name,
    };
    final accounts = _accounts;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Steam accounts', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        AddAccountForm(
          daemonId: widget.daemonId,
          onSent: () => unawaited(_load()),
        ),
        const SizedBox(height: 8),
        if (_loadError != null)
          Text('Could not load the accounts: $_loadError'),
        if (accounts == null && _loadError == null)
          const Center(child: CircularProgressIndicator())
        else if (accounts != null && accounts.isEmpty)
          const Text('No Steam accounts yet.'),
        for (final account in accounts ?? const <SteamAccount>[])
          _AccountTile(
            key: ValueKey('steam:account:${account.id}'),
            account: account,
            instanceNames: [
              for (final id in account.usedByInstanceIds) names[id] ?? id,
            ],
            refusal: _refusals[account.id],
            onReauth: () => unawaited(_reauth(account)),
            onRemove: () => unawaited(_remove(account)),
          ),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    super.key,
    required this.account,
    required this.instanceNames,
    required this.refusal,
    required this.onReauth,
    required this.onRemove,
  });

  final SteamAccount account;
  final List<String> instanceNames;
  final String? refusal;
  final VoidCallback onReauth;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                        account.username,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(steamAccountStatusLabel(account.status)),
                      Text(
                        instanceNames.isEmpty
                            ? 'Not used by any instance'
                            : 'Used by ${instanceNames.join(', ')}',
                      ),
                    ],
                  ),
                ),
                if (account.status == 'reauth_required')
                  TextButton(
                    key: ValueKey('steam:reauth:${account.id}'),
                    onPressed: onReauth,
                    child: const Text('Log in again'),
                  ),
                IconButton(
                  key: ValueKey('steam:remove:${account.id}'),
                  tooltip: 'Remove account',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onRemove,
                ),
              ],
            ),
            if (refusal != null)
              Padding(
                key: ValueKey('steam:in-use:${account.id}'),
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  instanceNames.isEmpty
                      ? 'Not removed: $refusal'
                      : 'Not removed: used by ${instanceNames.join(', ')}. '
                            'Unlink it there first.',
                  style: TextStyle(color: scheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Username, password and "remember" of a new Steam account. The password
/// goes out with the call and the field is emptied as it does; nothing else
/// keeps it.
class AddAccountForm extends ConsumerStatefulWidget {
  const AddAccountForm({super.key, required this.daemonId, this.onSent});

  final String daemonId;

  /// Called once the daemon accepted the request.
  final VoidCallback? onSent;

  @override
  ConsumerState<AddAccountForm> createState() => _AddAccountFormState();
}

class _AddAccountFormState extends ConsumerState<AddAccountForm> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _remember = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    if (username.isEmpty || _password.text.isEmpty || _busy) return;
    final connection = ref.read(daemonConnectionProvider(widget.daemonId));
    final password = _password.text;
    // Emptied as the call goes out: the field never shows it again.
    _password.clear();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await connection.addAccount(
        username,
        password,
        rememberPassword: _remember,
      );
      if (mounted) _username.clear();
      widget.onSent?.call();
    } on DaemonCallException catch (e) {
      if (mounted) setState(() => _error = _reason(e));
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        key: const ValueKey('steam:username'),
        controller: _username,
        decoration: const InputDecoration(labelText: 'Steam username'),
        autocorrect: false,
      ),
      TextField(
        key: const ValueKey('steam:password'),
        controller: _password,
        decoration: const InputDecoration(labelText: 'Password'),
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        onSubmitted: (_) => unawaited(_submit()),
      ),
      CheckboxListTile(
        key: const ValueKey('steam:remember'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('Remember the password'),
        subtitle: const Text(
          'Stored encrypted on the daemon host, so updates can log in again.',
        ),
        value: _remember,
        onChanged: (v) => setState(() => _remember = v ?? false),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          key: const ValueKey('steam:add'),
          onPressed: _busy ? null : () => unawaited(_submit()),
          child: const Text('Add account'),
        ),
      ),
    ],
  );
}

/// Adds an account from a dialog (the retry after a failed attempt).
Future<void> showAddAccountDialog(BuildContext context, String daemonId) =>
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('steam:add-dialog'),
        title: const Text('Add a Steam account'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: AddAccountForm(
              daemonId: daemonId,
              onSent: () => Navigator.pop(dialogContext),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

class _ReauthDialog extends ConsumerStatefulWidget {
  const _ReauthDialog({required this.daemonId, required this.account});

  final String daemonId;
  final SteamAccount account;

  @override
  ConsumerState<_ReauthDialog> createState() => _ReauthDialogState();
}

class _ReauthDialogState extends ConsumerState<_ReauthDialog> {
  final _password = TextEditingController();
  bool _remember = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty || _busy) return;
    final connection = ref.read(daemonConnectionProvider(widget.daemonId));
    final password = _password.text;
    _password.clear();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await connection.reauthAccount(
        widget.account.id,
        password,
        rememberPassword: _remember,
      );
      if (mounted) Navigator.pop(context);
    } on DaemonCallException catch (e) {
      if (mounted) setState(() => _error = _reason(e));
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Log in ${widget.account.username} again'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The saved login of ${widget.account.username} expired. Enter '
            'its password; Steam may ask for a Guard code.',
          ),
          TextField(
            key: const ValueKey('reauth:password'),
            controller: _password,
            decoration: const InputDecoration(labelText: 'Password'),
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            autofocus: true,
            onSubmitted: (_) => unawaited(_submit()),
          ),
          CheckboxListTile(
            key: const ValueKey('reauth:remember'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Remember the password'),
            value: _remember,
            onChanged: (v) => setState(() => _remember = v ?? false),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('reauth:submit'),
        onPressed: _busy ? null : () => unawaited(_submit()),
        child: const Text('Log in'),
      ),
    ],
  );
}

/// Links a Steam account to an instance (or unlinks it). Shown only for games
/// that log in with an account.
class InstanceAccountPicker extends ConsumerStatefulWidget {
  const InstanceAccountPicker({
    super.key,
    required this.daemonId,
    required this.instance,
  });

  final String daemonId;
  final Instance instance;

  @override
  ConsumerState<InstanceAccountPicker> createState() =>
      _InstanceAccountPickerState();
}

class _InstanceAccountPickerState extends ConsumerState<InstanceAccountPicker> {
  List<SteamAccount>? _accounts;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final connection = ref.read(daemonConnectionProvider(widget.daemonId));
    try {
      final transport = await connection.whenConnected();
      final plugin = await transport.getPlugin(widget.instance.pluginId);
      final login = plugin.summary.steamLogin;
      if (login != 'account' && login != 'account_optional') return;
      final accounts = await transport.listAccounts();
      if (mounted) setState(() => _accounts = accounts);
    } on Object {
      // No picker: an older daemon, or a plugin that is gone.
    }
  }

  Future<void> _link(String accountId) async {
    final connection = ref.read(daemonConnectionProvider(widget.daemonId));
    final instance = widget.instance;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _saving = true);
    try {
      await connection.transport.updateSettings(
        UpdateSettingsRequest(
          instanceId: instance.id,
          expectedRevision: instance.revision,
          settings: JsonDocument(
            json: jsonEncode(_withoutSecrets(instance.settings.json)),
            schemaVersion: instance.settings.schemaVersion,
          ),
          ports: instance.ports,
          steamAccountId: accountId,
        ),
      );
    } on DaemonCallException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(_reason(e))));
    } on StateError catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts;
    if (accounts == null) return const SizedBox.shrink();
    final linked = widget.instance.steamAccountId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          const Text('Steam account'),
          const SizedBox(width: 12),
          DropdownButton<String>(
            key: const ValueKey('instance:account'),
            value: linked,
            items: [
              const DropdownMenuItem(value: '', child: Text('None')),
              for (final a in accounts)
                DropdownMenuItem(
                  value: a.id,
                  child: Text(
                    a.status == 'ready'
                        ? a.username
                        : '${a.username} (${steamAccountStatusLabel(a.status)})',
                  ),
                ),
              if (linked.isNotEmpty && !accounts.any((a) => a.id == linked))
                DropdownMenuItem(value: linked, child: Text(linked)),
            ],
            onChanged: _saving ? null : (id) => unawaited(_link(id ?? '')),
          ),
        ],
      ),
    );
  }
}

/// The non-secret settings: the daemon sends secrets as `{"secret": true}`
/// markers, which a settings update must not carry.
Object? _withoutSecrets(String json) {
  Object? strip(Object? value) => switch (value) {
    Map<String, Object?>() when value['secret'] == true => null,
    Map<String, Object?>() => {
      for (final MapEntry(:key, :value) in value.entries)
        if (!(value is Map<String, Object?> && value['secret'] == true))
          key: strip(value),
    },
    _ => value,
  };
  try {
    return strip(jsonDecode(json));
  } on FormatException {
    return const <String, Object?>{};
  }
}
