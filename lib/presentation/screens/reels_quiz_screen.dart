import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/domain_model.dart';
import '../../data/models/question_model.dart';
import '../providers/database_provider.dart';
import '../widgets/bookmark_button.dart';

/// Reels-style quiz: one question per full screen, swipe up for the next.
///
/// Deliberately NOT built on quizProvider. That provider models a bounded,
/// scored session (fixed question list, final result screen). Reels is an
/// open-ended browse — there's no end, no final score to submit, and each
/// card owns its own answered/revealed state. Reusing the sequential
/// provider would have meant fighting it on every one of those points.
///
/// Questions are loaded in pages: an initial batch, then more fetched in the
/// background as the user approaches the end, so scrolling never blocks.
class ReelsQuizScreen extends ConsumerStatefulWidget {
  const ReelsQuizScreen({super.key});

  @override
  ConsumerState<ReelsQuizScreen> createState() => _ReelsQuizScreenState();
}

class _ReelsQuizScreenState extends ConsumerState<ReelsQuizScreen> {
  final _pageCtrl = PageController();
  final List<QuestionModel> _questions = [];
  final Set<String> _seenIds = {};

  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  int _correct = 0;
  int _answered = 0;

  /// Subject pool we draw from, reshuffled as we go.
  List<(DomainModel, SubjectModel)> _pool = [];
  int _poolCursor = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final domains = await ref.read(firestoreServiceProvider).fetchDomains();
      final pool = <(DomainModel, SubjectModel)>[];
      for (final d in domains.where((d) => d.isActive)) {
        for (final s in d.subjects.where((s) => s.isActive)) {
          pool.add((d, s));
        }
      }
      pool.shuffle();
      _pool = pool;

      if (_pool.isEmpty) {
        setState(() {
          _error = 'No content available yet.';
          _loading = false;
        });
        return;
      }
      await _loadMore(initial: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  /// Pulls another few subjects' worth of questions onto the end of the feed.
  Future<void> _loadMore({bool initial = false}) async {
    if (_loadingMore || _pool.isEmpty) return;
    _loadingMore = true;
    try {
      final repo = ref.read(questionRepositoryProvider);
      final batch = <QuestionModel>[];

      // Walk a few subjects per load; wrap around and reshuffle at the end so
      // the feed keeps going rather than dead-ending.
      var tries = 0;
      while (batch.length < 12 && tries < 6) {
        if (_poolCursor >= _pool.length) {
          _pool.shuffle();
          _poolCursor = 0;
        }
        final (d, s) = _pool[_poolCursor++];
        tries++;
        try {
          final qs = s.isShared
              ? await repo.getSharedSubjectQuestions(s.id)
              : await repo.getSubjectQuestionsOnDemand(d.id, s.id);
          for (final q in qs) {
            // Don't repeat a question already in the feed.
            if (_seenIds.add(q.id)) batch.add(q);
          }
        } catch (_) {
          // Skip a subject that fails rather than stopping the feed.
        }
      }

      batch.shuffle();
      if (mounted) {
        setState(() {
          _questions.addAll(batch);
          if (initial) _loading = false;
        });
      }
    } finally {
      _loadingMore = false;
    }
  }

  void _onAnswered(bool wasCorrect) {
    setState(() {
      _answered++;
      if (wasCorrect) _correct++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reels')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reels')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error ?? 'No questions available yet.',
                textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Reels'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                _answered == 0 ? '' : '$_correct / $_answered',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageCtrl,
        scrollDirection: Axis.vertical,
        itemCount: _questions.length,
        onPageChanged: (i) {
          // Prefetch well before the end so the swipe never stalls.
          if (i >= _questions.length - 4) _loadMore();
        },
        itemBuilder: (context, i) => _ReelCard(
          key: ValueKey(_questions[i].id),
          question: _questions[i],
          isLast: i == _questions.length - 1,
          onAnswered: _onAnswered,
        ),
      ),
    );
  }
}

/// One full-screen question card. Holds its own answer state so swiping back
/// to an earlier card still shows what you picked.
class _ReelCard extends StatefulWidget {
  final QuestionModel question;
  final bool isLast;
  final void Function(bool wasCorrect) onAnswered;

  const _ReelCard({
    super.key,
    required this.question,
    required this.isLast,
    required this.onAnswered,
  });

  @override
  State<_ReelCard> createState() => _ReelCardState();
}

class _ReelCardState extends State<_ReelCard> {
  int? _picked;

  bool get _answered => _picked != null;

  void _pick(int i) {
    if (_answered) return; // one shot per card
    setState(() => _picked = i);
    widget.onAnswered(i == widget.question.correctOptionIndex);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = widget.question;
    final correct = q.correctOptionIndex;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${q.domainName} • ${q.subjectName}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                BookmarkButton(question: q),
              ],
            ),
            const Spacer(),
            Text(
              q.question,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold, height: 1.35),
            ),
            const SizedBox(height: 24),
            for (var i = 0; i < q.options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _option(theme, i, correct),
              ),
            if (_answered && q.explanation.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(q.explanation,
                    style: theme.textTheme.bodyMedium),
              ),
            ],
            const Spacer(),
            // Swipe affordance — a vertical PageView isn't obvious otherwise.
            Opacity(
              opacity: 0.6,
              child: Column(
                children: [
                  Icon(Icons.keyboard_arrow_up_rounded,
                      color: theme.hintColor),
                  Text(
                      widget.isLast
                          ? 'Loading more...'
                          : 'Swipe up for next',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(ThemeData theme, int i, int correct) {
    Color? bg;
    Color? border;
    IconData? icon;

    if (_answered) {
      if (i == correct) {
        bg = Colors.green.withOpacity(0.15);
        border = Colors.green;
        icon = Icons.check_circle_rounded;
      } else if (i == _picked) {
        bg = theme.colorScheme.error.withOpacity(0.12);
        border = theme.colorScheme.error;
        icon = Icons.cancel_rounded;
      }
    }

    return InkWell(
      onTap: () => _pick(i),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bg ?? theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: border ?? Colors.transparent,
            width: border == null ? 0 : 2,
          ),
        ),
        child: Row(
          children: [
            Expanded(child: Text(widget.question.options[i])),
            if (icon != null) Icon(icon, color: border),
          ],
        ),
      ),
    );
  }
}
