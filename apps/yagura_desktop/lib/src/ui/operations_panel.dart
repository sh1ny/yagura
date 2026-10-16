import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yagura_proto/yagura_proto.dart';

import '../connection.dart';
import '../providers.dart';

String operationStatusLabel(OperationStatus status) => switch (status) {
  OperationStatus.OPERATION_STATUS_QUEUED => 'queued',
  OperationStatus.OPERATION_STATUS_RUNNING => 'in progress',
  OperationStatus.OPERATION_STATUS_WAITING_FOR_INPUT => 'waiting for input',
  OperationStatus.OPERATION_STATUS_SUCCEEDED => 'succeeded',
  OperationStatus.OPERATION_STATUS_FAILED => 'failed',
  OperationStatus.OPERATION_STATUS_CANCELLED => 'cancelled',
  OperationStatus.OPERATION_STATUS_INTERRUPTED => 'interrupted',
  _ => 'unknown',
};

/// Steps and progress of the daemon's operations until they end.
class OperationsPanel extends ConsumerWidget {
  const OperationsPanel({super.key, required this.daemonId});

  final String daemonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operations =
        ref.watch(operationsProvider(daemonId)).value ?? const [];
    if (operations.isEmpty) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        for (final operation in operations.reversed)
          _OperationCard(operation: operation),
      ],
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({required this.operation});

  final OperationState operation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = operation.percent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(operation.kind, style: theme.textTheme.titleSmall),
                const SizedBox(width: 8),
                Text(operationStatusLabel(operation.status)),
              ],
            ),
            for (var i = 0; i < operation.steps.length; i++)
              Row(
                children: [
                  Icon(
                    i == operation.steps.length - 1 && !operation.ended
                        ? Icons.play_arrow
                        : Icons.check,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(operation.steps[i]),
                ],
              ),
            if (!operation.ended)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(
                  value: percent == null ? null : percent / 100,
                ),
              ),
            if (percent != null && !operation.ended)
              Text('${percent.round()}%'),
            if (operation.message.isNotEmpty) Text(operation.message),
          ],
        ),
      ),
    );
  }
}
