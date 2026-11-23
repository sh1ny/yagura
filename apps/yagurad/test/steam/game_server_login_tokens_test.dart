import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yagurad/src/files/instance_fs.dart';
import 'package:yagurad/src/host/daemon.dart';
import 'package:yagurad/src/instances/instance.dart';
import 'package:yagurad/src/operations/operations.dart';
import 'package:yagurad/src/process/process.dart';

import '../support/daemon_support.dart';
import '../support/secret_support.dart';

const _token = 'GSLT-4F9A1C77-SECRET-TOKEN';

/// Valheim with a `gslt` secret setting named in `steam.gslt` and handed to the
/// server as `-gslt=<token>`.
Future<(Daemon, Instance)> _withGslt(
  TestEnv env, {
  required bool required,
  bool secretRequired = false,
}) async {
  env.installValheim(
    from: '  login: anonymous\n',
    to:
        '  login: anonymous\n'
        '  gslt: { setting: gslt, required: $required }\n',
  );
  env.editValheim(
    '    label: Server password\n    group: General\n',
    '    label: Server password\n    group: General\n'
        '  gslt:\n    type: secret\n    label: Game Server Login Token\n'
        '${secretRequired ? '    required: true\n' : ''}',
  );
  env.editValheim(
    '    - -batchmode\n',
    '    - -batchmode\n    - "-gslt={{secrets.gslt}}"\n',
  );
  final daemon = await env.start(secretProtector: FakeSecretProtector(devSid));
  return (daemon, await createInstalled(daemon));
}

void main() {
  test('token_injected_at_launch', () async {
    final env = TestEnv();
    final (daemon, instance) = await _withGslt(env, required: true);
    daemon.instances.setSecret(instance.id, 'gslt', _token);

    final done = await runStart(daemon, instance.id);

    expect(done.status, OperationStatus.succeeded, reason: done.resultMessage);
    final launch = env.process.launches.single;
    // The launched process receives the value, through the secrets channel.
    expect(launch.secrets, {'gslt': _token});
    final secretArg = launch.secretArguments.single;
    expect(secretArg.setting, 'gslt');
    expect(secretArg.prefix, '-gslt=');
    expect(launch.args[secretArg.index], '-gslt=***');
    expect(launch.resolvedArgs()[secretArg.index], '-gslt=$_token');
    // Everything else the daemon reports holds no value.
    expect(launch.args.join('\n'), isNot(contains(_token)));
    final history = [
      for (final op in daemon.operations.listForInstance(instance.id))
        jsonEncode([
          op.kind.name,
          op.status.wireName,
          op.currentStep,
          op.resultReason,
          op.resultMessage,
          op.warnings,
        ]),
    ].join('\n');
    expect(history, isNot(contains(_token)));
    expect(history, isNot(contains('GSLT-')));
  });

  test('the run files hold the secret entry and never the value', () async {
    final env = TestEnv();
    final (daemon, instance) = await _withGslt(env, required: true);
    daemon.instances.setSecret(instance.id, 'gslt', _token);
    await runStart(daemon, instance.id);
    final launch = env.process.launches.single;
    final run = p.join(launch.instanceDirectory, '.yagura', 'run', 'test-run');
    final files = RunFiles(run, fs: InstanceFs(launch.instanceDirectory));

    files.writeLaunch(launch);

    final text = File(files.launchPath).readAsStringSync();
    expect(text, isNot(contains(_token)));
    final args = (jsonDecode(text) as Map<String, Object?>)['args']! as List;
    expect(args, contains('-nographics'));
    expect(args.whereType<Map<String, Object?>>().single, {
      'secret': 'gslt',
      'prefix': '-gslt=',
      'suffix': '',
    });
    // The relay reads the same entry back as a secret slot.
    final read = files.readLaunch()!;
    expect(read.secretArguments.single.setting, 'gslt');
    expect(read.args[read.secretArguments.single.index], '-gslt=***');
    expect(read.secrets, isEmpty);
  });

  test('required_token_missing', () async {
    final env = TestEnv();
    final (daemon, instance) = await _withGslt(env, required: true);

    expect(
      () => daemon.instances.start(instance.id),
      failsWith('gslt_required', messageHas: ['gslt']),
    );

    expect(env.process.launches, isEmpty, reason: 'no process is launched');
    expect(daemon.instances.get(instance.id).state, InstanceState.stopped);
  });

  test('the token is checked before the secret setting is', () async {
    final env = TestEnv();
    final (daemon, instance) = await _withGslt(
      env,
      required: true,
      secretRequired: true,
    );

    expect(
      () => daemon.instances.start(instance.id),
      failsWith('gslt_required'),
    );
    expect(env.process.launches, isEmpty);
  });

  test(
    'an optional token left unset starts the server without the argument',
    () async {
      final env = TestEnv();
      final (daemon, instance) = await _withGslt(env, required: false);

      final done = await runStart(daemon, instance.id);

      expect(
        done.status,
        OperationStatus.succeeded,
        reason: done.resultMessage,
      );
      final launch = env.process.launches.single;
      expect(launch.secrets, isEmpty);
      expect(launch.secretArguments, isEmpty);
      expect(launch.args.where((a) => a.startsWith('-gslt')), isEmpty);
    },
  );
}
