import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../data/models/error_log_model.dart';
import '../../providers/database_provider.dart';

/// Admin > Error logs. Every crash/error caught anywhere in the app (via
/// ErrorReporter) lands here — the point of the whole "something went
/// wrong, we've reported it" flow shown to users.
class AdminErrorLogsScreen extends ConsumerStatefulWidget {
  const AdminErrorLogsScreen({super.key});

  @override
  ConsumerState<AdminErrorLogsScreen> createState() =>
      _AdminErrorLogsScreenState();
}

class _AdminErrorLogsScreenState extends ConsumerState<AdminErrorLogsScreen> {
  /// Resolved errors are hidden by default so the list shows what still
  /// needs attention.
  bool _showResolved = false;

  /// Ids currently ticked. Empty means normal (non-selection) mode.
  final Set<String> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  /// Builds a plain-text report of the visible logs.
  ///
  /// Text rather than PDF/Word on purpose: PDF needs an extra native-ish
  /// package and .docx is genuinely painful to generate, whereas text goes
  /// straight into the share sheet (email, WhatsApp, Drive, a file) and can
  /// be opened by anything. Same practical result, no new dependency.
  String _buildReport(List<ErrorLogModel> logs) {
    final b = StringBuffer()
      ..writeln('GK QUIZ HERO — ERROR LOG EXPORT')
      ..writeln('Generated: ${DateTime.now().toLocal()}')
      ..writeln('Entries: ${logs.length}')
      ..writeln('=' * 60)
      ..writeln();
    for (var i = 0; i < logs.length; i++) {
      final l = logs[i];
      b
        ..writeln('#${i + 1}  ${l.resolved ? '[RESOLVED]' : '[OPEN]'}')
        ..writeln('When    : ${l.createdAt?.toLocal() ?? 'unknown'}')
        ..writeln('Platform: ${l.platform}   App version: ${l.appVersion}')
        ..writeln('User    : ${l.userEmail ?? l.userUid ?? 'not signed in'}')
        ..writeln('Context : ${l.context ?? '-'}')
        ..writeln('Message : ${l.message}')
        ..writeln('Stack   :')
        ..writeln(l.stackTrace)
        ..writeln('-' * 60)
        ..writeln();
    }
    return b.toString();
  }

  Future<void> _clearAll() async {
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
      // `mounted` (the State's), not `context.mounted`: inside a State the
      // context belongs to this widget, so the State's own lifecycle is the
      // correct thing to check after an await.
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logsAsync = ref.watch(errorLogsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_selecting
            ? '${_selected.length} selected'
            : 'Error logs'),
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(_selected.clear),
              )
            : null,
        actions: [
          if (_selecting) ...[
            IconButton(
              tooltip: 'Mark selected solved',
              icon: const Icon(Icons.check_circle_outline_rounded),
              onPressed: () async {
                final ids = _selected.toList();
                // Grab the messenger BEFORE awaiting. Using a BuildContext
                // after an async gap is the classic source of "used after
                // dispose" crashes; capturing it up front sidesteps the
                // question entirely.
                final messenger = ScaffoldMessenger.of(context);
                setState(_selected.clear);
                try {
                  await ref
                      .read(firestoreServiceProvider)
                      .setErrorLogsResolved(ids, true);
                } catch (e) {
                  messenger
                      .showSnackBar(SnackBar(content: Text('Failed: $e')));
                }
              },
            ),
            IconButton(
              tooltip: 'Delete selected',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ids = _selected.toList();
                // Captured BEFORE the dialog: showDialog is itself an async
                // gap, so grabbing the messenger afterwards still touches a
                // context that may no longer be valid.
                final messenger = ScaffoldMessenger.of(context);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('Delete ${ids.length} log(s)?'),
                    content: const Text('This cannot be undone.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (ok != true) return;
                setState(_selected.clear);
                try {
                  await ref
                      .read(firestoreServiceProvider)
                      .deleteErrorLogs(ids);
                } catch (e) {
                  messenger
                      .showSnackBar(SnackBar(content: Text('Failed: $e')));
                }
              },
            ),
          ],
          if (!_selecting)
          IconButton(
            tooltip: _showResolved ? 'Hide resolved' : 'Show resolved',
            icon: Icon(_showResolved
                ? Icons.filter_alt_off_rounded
                : Icons.filter_alt_rounded),
            onPressed: () => setState(() => _showResolved = !_showResolved),
          ),
          IconButton(
            tooltip: 'Export as text',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () {
              final all = ref.read(errorLogsProvider).valueOrNull ?? const [];
              final visible = _showResolved
                  ? all
                  : all.where((l) => !l.resolved).toList();
              if (visible.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Nothing to export.')));
                return;
              }
              SharePlus.instance.share(ShareParams(
                text: _buildReport(visible),
                subject: 'GK Quiz Hero error logs',
              ));
            },
          ),
          IconButton(
            tooltip: 'Clear all',
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: _clearAll,
          ),
        ],
      ),
      body: logsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (all) {
          final logs =
              _showResolved ? all : all.where((l) => !l.resolved).toList();
          if (logs.isEmpty) {
            return Center(
                child: Text(all.isEmpty
                    ? 'No errors logged. Good sign!'
                    : 'No open errors — everything is marked resolved.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: logs.length,
            itemBuilder: (context, i) => _logCard(theme, logs[i]),
          );
        },
      ),
    );
  }

  Widget _logCard(ThemeData theme, ErrorLogModel log) {
    return Card(
      child: _selecting
          ? CheckboxListTile(
              value: _selected.contains(log.id),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.add(log.id);
                } else {
                  _selected.remove(log.id);
                }
              }),
              title: Text(log.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text(
                '${log.platform} • v${log.appVersion}'
                '${log.resolved ? ' • RESOLVED' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            )
          : ExpansionTile(
        leading: Icon(
            log.resolved
                ? Icons.check_circle_rounded
                : Icons.warning_amber_rounded,
            color: log.resolved ? Colors.green : theme.colorScheme.error),
        // ExpansionTile has no onLongPress of its own, so the gesture goes
        // on the title widget instead — long-press there starts multi-select
        // while a normal tap still expands the row as before.
        title: GestureDetector(
          onLongPress: () => setState(() => _selected.add(log.id)),
          child: Text(
            log.message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: Icon(
                          log.resolved
                              ? Icons.undo_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 18),
                      label: Text(log.resolved ? 'Reopen' : 'Mark solved'),
                      onPressed: () => ref
                          .read(firestoreServiceProvider)
                          .setErrorLogResolved(log.id, !log.resolved),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Delete'),
                      onPressed: () => ref
                          .read(firestoreServiceProvider)
                          .deleteErrorLog(log.id),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
