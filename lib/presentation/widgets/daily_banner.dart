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
  /// 'strip' is a single compact line — the one placement guaranteed to be
  /// seen, since it sits above the fold and costs almost no height. Tapping
  /// opens the full quote.
  ///
  /// 'both' renders thought + pick together (used outside the home screen).
  /// 'thought' and 'pick' render one half each, so the home screen can put
  /// the actionable pick near the top and the quote at the bottom —
  /// decoration should not outrank content.
  final String mode;
  const DailyBanner({super.key, this.mode = 'both'});

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

  /// Full quote in a sheet, with attribution. Used by the compact strip.
  static void _showFull(BuildContext context, DailyThought thought) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final t = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.format_quote_rounded,
                      color: t.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Thought of the day',
                      style: t.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 16),
                Text(thought.text,
                    style: t.textTheme.titleMedium
                        ?.copyWith(height: 1.5, fontStyle: FontStyle.italic)),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('— ${thought.author}',
                      style: t.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        );
      },
    );
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

    // One-line strip. Truncation is the trade-off for always being visible;
    // the full text is one tap away rather than a scroll away.
    if (mode == 'strip') {
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showFull(context, thought),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.format_quote_rounded,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  thought.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic, color: theme.hintColor),
                ),
              ),
              Icon(Icons.expand_more_rounded,
                  size: 18, color: theme.hintColor),
            ],
          ),
        ),
      );
    }

    // Compact, actionable half.
    if (mode == 'pick') {
      if (pick == null) return const SizedBox.shrink();
      return Card(
        color: theme.colorScheme.primaryContainer,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _open(context, pick),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onPrimaryContainer
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.auto_awesome_rounded,
                      size: 20, color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("TODAY'S PICK",
                          style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer
                                  .withValues(alpha: 0.7))),
                      Text(pick.subject.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: theme.colorScheme.onPrimaryContainer)),
                      Text(pick.domain.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer
                                  .withValues(alpha: 0.8))),
                    ],
                  ),
                ),
                Icon(Icons.play_circle_fill_rounded,
                    size: 32, color: theme.colorScheme.onPrimaryContainer),
              ],
            ),
          ),
        ),
      );
    }

    // Quote-only half: deliberately quiet, so it reads as a closing note
    // rather than competing with the content above it.
    if (mode == 'thought') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.format_quote_rounded,
                size: 20, color: theme.hintColor),
            const SizedBox(height: 4),
            Text(thought.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.5, fontStyle: FontStyle.italic)),
            const SizedBox(height: 8),
            Text('— ${thought.author}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

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
