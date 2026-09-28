import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/daily_thoughts.dart';
import '../../data/models/domain_model.dart';
import '../providers/database_provider.dart';
import '../screens/quiz_start_screen.dart';
import '../screens/sub_level_screen.dart';

/// Today's thought and today's suggested subject, in one card.
///
/// Both are chosen deterministically from the date, so every user sees the
/// same thing on the same day and it changes at midnight without any server,
/// scheduled job or extra reads. Nothing here costs Firestore quota — the
/// domains are already loaded for the home screen.
class DailyBanner extends ConsumerWidget {
  const DailyBanner({super.key});

  /// Picks one visible subject for today, spread across all domains.
  ///
  /// Uses day-of-epoch modulo the subject count, so the choice rotates
  /// through the whole catalogue rather than favouring the first domain.
  static ({DomainModel domain, SubjectModel subject})? _pickSubject(
      List<DomainModel> domains, DateTime date) {
    final options = <({DomainModel domain, SubjectModel subject})>[];
    for (final d in domains.where((d) => d.isActive)) {
      for (final s in d.subjects.where((s) => s.isActive)) {
        options.add((domain: d, subject: s));
      }
    }
    if (options.isEmpty) return null;
    final days = DateTime(date.year, date.month, date.day)
        .difference(DateTime(2020, 1, 1))
        .inDays;
    return options[days.abs() % options.length];
  }

  void _open(BuildContext context,
      ({DomainModel domain, SubjectModel subject}) pick) {
    final hasSubLevels =
        pick.subject.subLevels.any((sl) => sl.isActive) || pick.subject.isShared;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => hasSubLevels
          ? SubLevelScreen(domain: pick.domain, subject: pick.subject)
          : QuizStartScreen(
              domainId: pick.domain.id,
              domainName: pick.domain.name,
              subjectId: pick.subject.id,
              subjectName: pick.subject.name,
              isShared: pick.subject.isShared,
            ),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final thought = DailyThoughts.forDate(today);
    final domains = ref.watch(domainsProvider).valueOrNull ?? const [];
    final pick = _pickSubject(domains, today);

    return Card(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.format_quote_rounded,
                  size: 18, color: theme.colorScheme.onTertiaryContainer),
              const SizedBox(width: 8),
              Text('Thought of the day',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onTertiaryContainer)),
            ]),
            const SizedBox(height: 8),
            Text(
              thought.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.4,
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onTertiaryContainer),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              // Attribution is not optional: an unattributed quote is just
              // a slogan, and many circulating quotes are misattributed.
              child: Text('— ${thought.author}',
                  style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onTertiaryContainer)),
            ),
            if (pick != null) ...[
              const Divider(height: 22),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _open(context, pick),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 18, color: theme.colorScheme.onTertiaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Today's pick: ${pick.subject.name}",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color:
                                      theme.colorScheme.onTertiaryContainer)),
                          Text(
                            'from ${pick.domain.name} — try a few questions',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color:
                                    theme.colorScheme.onTertiaryContainer),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: theme.colorScheme.onTertiaryContainer),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
