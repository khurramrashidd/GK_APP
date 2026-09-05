import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/report_model.dart';
import '../providers/database_provider.dart';
import '../providers/reports_provider.dart';

/// The signed-in user's own reports — what they flagged, and any resolution.
/// Opening this screen clears the notification badge: every unseen resolved
/// report is marked seen as soon as the list loads.
class MyReportsScreen extends ConsumerStatefulWidget {
  const MyReportsScreen({super.key});

  @override
  ConsumerState<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends ConsumerState<MyReportsScreen> {
  bool _markedThisVisit = false;

  void _maybeMarkSeen(List<ReportModel> reports) {
    if (_markedThisVisit) return;
    final unseen = reports
        .where((r) => r.isResolved && !r.seenByReporter)
        .map((r) => r.id)
        .toList();
    if (unseen.isEmpty) return;
    _markedThisVisit = true;
    ref.read(firestoreServiceProvider).markReportsSeen(unseen);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reportsAsync = ref.watch(myReportsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Reports')),
      body: reportsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (reports) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _maybeMarkSeen(reports));

          if (reports.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "You haven't reported anything.\nSee something wrong in a "
                  'question? Tap "Report an issue" while reviewing it.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: reports.length,
            itemBuilder: (context, i) {
              final r = reports[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(
                          r.isResolved
                              ? Icons.check_circle_rounded
                              : Icons.hourglass_top_rounded,
                          size: 18,
                          color: r.isResolved
                              ? Colors.green
                              : theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(r.isResolved ? 'Resolved' : 'Open',
                            style: theme.textTheme.labelLarge?.copyWith(
                                color: r.isResolved
                                    ? Colors.green
                                    : theme.colorScheme.primary)),
                        const Spacer(),
                        Text(r.reason, style: theme.textTheme.bodySmall),
                      ]),
                      const SizedBox(height: 8),
                      Text(r.questionText,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        '${r.domainName} • ${r.subjectName}'
                        '${r.subLevelName != null ? ' • ${r.subLevelName}' : ''}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.hintColor),
                      ),
                      if (r.note.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('Your note: ${r.note}',
                            style: theme.textTheme.bodySmall),
                      ],
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Resolution',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(r.resolutionNote!),
                            ],
                          ),
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
    );
  }
}
