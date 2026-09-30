import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/question_model.dart';
import '../../data/models/report_model.dart';
import '../providers/auth_provider.dart';
import '../providers/database_provider.dart';

/// "Report an issue" button. Opens a small dialog (reason + optional note),
/// then submits a [ReportModel] built entirely from [question]'s own fields
/// — every question already carries its domain/subject/sub-level path, so
/// nothing extra needs to be passed in from the calling screen.
class ReportIssueButton extends ConsumerWidget {
  final QuestionModel question;
  final bool compact;

  const ReportIssueButton({
    super.key,
    required this.question,
    this.compact = false,
  });

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(profileProvider);
    if (profile == null) return;

    var reason = ReportModel.reasons.first;
    final noteCtrl = TextEditingController();

    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Report an issue'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  question.question,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(ctx)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(ctx).hintColor),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: reason,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: "What's wrong?"),
                  items: ReportModel.reasons
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) =>
                      setDialogState(() => reason = v ?? reason),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Details (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Submit')),
          ],
        ),
      ),
    );

    if (submitted != true || !context.mounted) return;

    final report = ReportModel(
      id: '',
      questionId: question.id,
      questionText: question.question,
      domainId: question.domainId,
      domainName: question.domainName,
      subjectId: question.subjectId,
      subjectName: question.subjectName,
      subLevelId: question.subLevelId,
      subLevelName: question.subLevelName,
      reportedByUid: profile.uid,
      reporterName:
          profile.name.isNotEmpty ? profile.name : profile.displayName,
      reporterEmail: profile.email,
      reason: reason,
      note: noteCtrl.text.trim(),
    );

    try {
      await ref.read(firestoreServiceProvider).submitReport(report);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Thanks — we'll take a look.")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not submit: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const icon = Icon(Icons.flag_outlined, size: 18);
    const label = Text('Report an issue');

    if (compact) {
      return TextButton.icon(
          icon: icon, label: label, onPressed: () => _open(context, ref));
    }
    return OutlinedButton.icon(
        icon: icon, label: label, onPressed: () => _open(context, ref));
  }
}
