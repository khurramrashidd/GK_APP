import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/report_model.dart';
import '../../providers/database_provider.dart';
import '../../providers/reports_provider.dart';
import 'admin_edit_question_screen.dart';

class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  ConsumerState<AdminReportsScreen> createState() =>
      _AdminReportsScreenState();
}

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen> {
  bool _showOpenOnly = true;
  bool _busy = false;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Open the reported question for editing. If the admin saves a fix, offer
  /// to resolve the report right away (with a default note) so the two steps
  /// flow together.
  Future<void> _openAndEdit(ReportModel r) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => AdminEditQuestionScreen(questionId: r.questionId),
    ));
    if (saved == true && mounted) {
      final resolveNow = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Resolve this report?'),
          content: const Text(
              'You saved a fix. Mark this report resolved and notify the '
              'person who reported it?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not yet')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Resolve')),
          ],
        ),
      );
      if (resolveNow == true) {
        setState(() => _busy = true);
        try {
          await ref
              .read(firestoreServiceProvider)
              .resolveReport(r.id, 'Fixed the question — thanks for flagging it.');
          _snack('Resolved — the reporter will see it.');
        } catch (e) {
          _snack('Could not resolve: $e');
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      }
    }
  }

  Future<void> _resolve(ReportModel r) async {
    final ctrl = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resolve report'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.questionText, style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'What did you do about it?',
                hintText:
                    'e.g. "Fixed the correct answer" or "Confirmed correct, no change needed"',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Mark resolved')),
        ],
      ),
    );
    if (note == null || note.isEmpty) return;

    setState(() => _busy = true);
    try {
      await ref.read(firestoreServiceProvider).resolveReport(r.id, note);
      _snack('Marked resolved — the reporter will see it.');
    } catch (e) {
      _snack('Could not resolve: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reportsAsync = ref.watch(adminReportsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Open')),
                ButtonSegment(value: false, label: Text('Resolved')),
              ],
              selected: {_showOpenOnly},
              onSelectionChanged: (s) =>
                  setState(() => _showOpenOnly = s.first),
            ),
          ),
          Expanded(
            child: reportsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (reports) {
                final filtered = reports
                    .where((r) => _showOpenOnly ? r.isOpen : r.isResolved)
                    .toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(_showOpenOnly
                        ? 'No open reports. All clear!'
                        : 'Nothing resolved yet.'),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final r = filtered[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: Text(r.reason,
                                    style: theme.textTheme.labelLarge
                                        ?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.bold)),
                              ),
                              Text(
                                r.createdAt != null
                                    ? '${r.createdAt!.day}/${r.createdAt!.month}/${r.createdAt!.year}'
                                    : '',
                                style: theme.textTheme.bodySmall,
                              ),
                            ]),
                            const SizedBox(height: 6),
                            Text(r.questionText,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(
                              '${r.domainName} • ${r.subjectName}'
                              '${r.subLevelName != null ? ' • ${r.subLevelName}' : ''}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.hintColor),
                            ),
                            if (r.note.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(r.note, style: theme.textTheme.bodyMedium),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              'Reported by ${r.reporterName} (${r.reporterEmail})',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.hintColor),
                            ),
                            if (r.isResolved && r.resolutionNote != null) ...[
                              const Divider(height: 20),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.secondaryContainer
                                      .withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(r.resolutionNote!),
                              ),
                            ],
                            if (r.isOpen) ...[
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.edit_rounded,
                                        size: 18),
                                    label: const Text('Open & edit'),
                                    onPressed:
                                        _busy ? null : () => _openAndEdit(r),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.icon(
                                    icon: const Icon(Icons.check_rounded,
                                        size: 18),
                                    label: const Text('Resolve'),
                                    onPressed: _busy ? null : () => _resolve(r),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
