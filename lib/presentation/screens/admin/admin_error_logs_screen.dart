import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/error_log_model.dart';
import '../../providers/database_provider.dart';

/// Admin > Error logs. Every crash/error caught anywhere in the app (via
/// ErrorReporter) lands here — the point of the whole "something went
/// wrong, we've reported it" flow shown to users.
class AdminErrorLogsScreen extends ConsumerWidget {
  const AdminErrorLogsScreen({super.key});

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all error logs?'),
        content: const Text('This permanently deletes every logged error.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(firestoreServiceProvider).clearAllErrorLogs();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final logsAsync = ref.watch(errorLogsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Error logs'),
        actions: [
          IconButton(
            tooltip: 'Clear all',
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: () => _clearAll(context, ref),
          ),
        ],
      ),
      body: logsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (logs) {
          if (logs.isEmpty) {
            return const Center(child: Text('No errors logged. Good sign!'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: logs.length,
            itemBuilder: (context, i) => _logCard(context, ref, theme, logs[i]),
          );
        },
      ),
    );
  }

  Widget _logCard(
      BuildContext context, WidgetRef ref, ThemeData theme, ErrorLogModel log) {
    return Card(
      child: ExpansionTile(
        leading: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
        title: Text(
          log.message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        subtitle: Text(
          '${log.platform} • v${log.appVersion}'
          '${log.context != null ? ' • ${log.context}' : ''}'
          '${log.createdAt != null ? ' • ${log.createdAt!.toLocal()}' : ''}',
          style: theme.textTheme.bodySmall,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (log.userEmail != null) ...[
                  Text('User: ${log.userEmail}',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                ],
                Text('Stack trace',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    log.stackTrace,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Delete this'),
                    onPressed: () => ref
                        .read(firestoreServiceProvider)
                        .deleteErrorLog(log.id),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
