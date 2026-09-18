import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/sound_service.dart';
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
  /// When true the widget renders bare (no Scaffold/AppBar) so it can sit
  /// inside the home screen's body as the default experience.
  final bool embedded;
  const ReelsQuizScreen({super.key, this.embedded = false});

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

  /// Consecutive correct answers. Reset on a wrong answer — this is the
  /// number the streak badge shows.
  int _streak = 0;
  int _bestStreak = 0;

  /// Counters for the periodic "how you're doing" card. Reset each time one
  /// is shown, so each card reports that block of questions, not all time.
  int _blockCorrect = 0;
  int _blockAnswered = 0;

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

  /// Two-tone gradients for card backgrounds. Chosen for contrast against
  /// white text and to stay visually calm — no imagery, no music, nothing
  /// that could be objectionable.
  /// Soft, light two-tone palettes with DARK text on top.
  ///
  /// The first version used saturated dark gradients with white text, which
  /// read as heavy and made the question compete with the background. These
  /// are pastel-weight instead: enough colour to feel lively, light enough
  /// that near-black text sits comfortably on them at any size.
  static const List<List<Color>> gradients = [
    [Color(0xFFFFF1EB), Color(0xFFACE0F9)], // peach -> sky
    [Color(0xFFE0F2F1), Color(0xFFB2EBF2)], // mint -> aqua
    [Color(0xFFFDF6E3), Color(0xFFFFE0B2)], // cream -> apricot
    [Color(0xFFEDE7F6), Color(0xFFD1C4E9)], // lilac -> lavender
    [Color(0xFFE8F5E9), Color(0xFFC8E6C9)], // pale green -> sage
    [Color(0xFFFCE4EC), Color(0xFFF8BBD0)], // blush -> rose
    [Color(0xFFE3F2FD), Color(0xFFBBDEFB)], // ice -> cornflower
    [Color(0xFFFFF8E1), Color(0xFFFFECB3)], // vanilla -> honey
    [Color(0xFFF3E5F5), Color(0xFFE1BEE7)], // orchid -> mauve
    [Color(0xFFE0F7FA), Color(0xFFB2DFDB)], // glacier -> teal mist
  ];


  /// Stable per-question gradient: the same question always looks the same,
  /// derived from its id rather than its position in the feed (which shifts
  /// as more load).
  static List<Color> gradientFor(String id) {
    final h = id.codeUnits.fold<int>(0, (a, b) => a + b);
    return gradients[h % gradients.length];
  }

  void _onAnswered(bool wasCorrect) {
    setState(() {
      _answered++;
      _blockAnswered++;
      if (wasCorrect) {
        _correct++;
        _blockCorrect++;
        _streak++;
        if (_streak > _bestStreak) _bestStreak = _streak;
      } else {
        _streak = 0;
      }
    });
  }

  /// Every 10 answers, slot in a progress card. Tracked by answer count
  /// rather than scroll position so skipping past questions without
  /// answering doesn't trigger it.
  bool get _shouldShowSummary => _blockAnswered >= 10;

  void _consumeSummary() {
    setState(() {
      _blockAnswered = 0;
      _blockCorrect = 0;
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

    final pager = PageView.builder(
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
          gradient: gradientFor(_questions[i].id),
          streak: _streak,
          onSummaryDue: _shouldShowSummary
              ? () {
                  final c = _blockCorrect;
                  final a = _blockAnswered;
                  _consumeSummary();
                  return (correct: c, total: a, best: _bestStreak);
                }
              : null,
        ),
      );

    if (widget.embedded) return pager;

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
      body: pager,
    );
  }
}

/// Shared ink colours for the light reel backgrounds.
class _ReelsPalette {
  static const Color ink = Color(0xFF1A1A2E);
  static const Color inkSoft = Color(0xFF4A4A68);
}

/// One full-screen question card. Holds its own answer state so swiping back
/// to an earlier card still shows what you picked.
class _ReelCard extends StatefulWidget {
  final QuestionModel question;
  final bool isLast;
  final void Function(bool wasCorrect) onAnswered;
  final List<Color> gradient;

  /// Current consecutive-correct run, shown as a badge.
  final int streak;

  /// Non-null when a progress card is due after this question. Calling it
  /// returns the block's figures AND resets the counter, so it fires once.
  final ({int correct, int total, int best}) Function()? onSummaryDue;

  const _ReelCard({
    super.key,
    required this.question,
    required this.isLast,
    required this.onAnswered,
    required this.gradient,
    this.streak = 0,
    this.onSummaryDue,
  });

  @override
  State<_ReelCard> createState() => _ReelCardState();
}

class _ReelCardState extends State<_ReelCard> {
  int? _picked;

  bool get _answered => _picked != null;

  ({int correct, int total, int best})? _summary;

  void _pick(int i) {
    if (_answered) return; // one shot per card
    final correct = i == widget.question.correctOptionIndex;

    // Sound + haptic feedback. See SoundService for why these are system
    // sounds today and how to swap in real audio files.
    if (correct) {
      SoundService.correct();
    } else {
      SoundService.wrong();
    }

    setState(() => _picked = i);
    widget.onAnswered(correct);

    // Pull the block summary (if one is due) AFTER reporting the answer, so
    // this question is included in the figures.
    final due = widget.onSummaryDue;
    if (due != null) {
      setState(() => _summary = due());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = widget.question;
    final correct = q.correctOptionIndex;

    return GestureDetector(
      // Double-tap anywhere to bookmark — the Instagram-style gesture people
      // already expect in a vertical feed.
      onDoubleTap: () {
        HapticFeedback.selectionClick();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
              content: Text('Use the bookmark icon to save this question'),
              duration: Duration(seconds: 1)));
      },
      child: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: widget.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      // Soft geometric pattern painted over the gradient. Deliberately very
      // low contrast: it should add texture you notice only if you look,
      // never something that competes with the question text.
      child: CustomPaint(
        painter: _SoftPatternPainter(seed: widget.question.id),
        child: SafeArea(
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
                        ?.copyWith(color: _ReelsPalette.inkSoft),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.streak >= 2)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('🔥 ${widget.streak}',
                        style: const TextStyle(
                            color: _ReelsPalette.ink,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                _difficultyBadge(q.difficulty),
                BookmarkButton(question: q),
              ],
            ),
            // Scrollable middle: a long question + 4 options + explanation
            // overflows a fixed Column on shorter screens (the crash log
            // showed "RenderFlex overflowed by 32 pixels"). Expanded +
            // SingleChildScrollView lets it scroll instead of overflowing,
            // while the header and swipe hint stay pinned.
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            Text(
              q.question,
              style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  height: 1.35,
                  color: _ReelsPalette.ink),
            ),
            const SizedBox(height: 24),
            for (var i = 0; i < q.options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _option(theme, i, correct),
              ),
            // Periodic progress card. This is the block summary captured
            // when this question was answered.
            if (_summary != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    const Text('Nice progress!',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _ReelsPalette.ink)),
                    const SizedBox(height: 4),
                    Text(
                      'You got ${_summary!.correct} of ${_summary!.total} '
                      'right in this batch  •  best streak '
                      '${_summary!.best}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _ReelsPalette.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
            if (_answered && q.explanation.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(q.explanation,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: _ReelsPalette.ink)),
              ),
            ],
                  ],
                ),
              ),
            ),
            // Swipe affordance — a vertical PageView isn't obvious otherwise.
            Opacity(
              opacity: 0.6,
              child: Column(
                children: [
                  const Icon(Icons.keyboard_arrow_up_rounded,
                      color: _ReelsPalette.inkSoft),
                  Text(
                      widget.isLast
                          ? 'Loading more...'
                          : 'Swipe up for next',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: _ReelsPalette.inkSoft)),
                ],
              ),
            ),
          ],
          ),
        ),
        ),
      ),
      ),
    );
  }

  /// Small difficulty pill. Colour-coded so it reads at a glance without
  /// needing the label to be long.
  Widget _difficultyBadge(int difficulty) {
    final (label, colour) = switch (difficulty) {
      1 => ('Easy', Colors.greenAccent),
      2 => ('Medium', Colors.amberAccent),
      _ => ('Hard', Colors.redAccent),
    };
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colour.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              color: colour, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _option(ThemeData theme, int i, int correct) {
    Color? bg;
    Color? border;
    IconData? icon;

    if (_answered) {
      if (i == correct) {
        bg = Colors.green.shade600;
        border = Colors.white;
        icon = Icons.check_circle_rounded;
      } else if (i == _picked) {
        bg = Colors.red.shade700;
        border = Colors.white;
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
          // Translucent white over the gradient keeps every option legible
          // whatever colours the card drew.
          color: bg ?? Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: border ?? Colors.white,
            width: border == null ? 1 : 2,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(widget.question.options[i],
                  style: TextStyle(
                      color: _answered && (i == correct || i == _picked)
                          ? Colors.white
                          : _ReelsPalette.ink,
                      fontWeight: FontWeight.w500)),
            ),
            if (icon != null) Icon(icon, color: Colors.white),
          ],
        ),
      ),
    );
  }
}


/// Faint circles scattered over the gradient — texture without noise.
///
/// Positions derive from the question id, so a given question always looks
/// identical rather than reshuffling on every rebuild (which would flicker
/// as the widget repaints).
class _SoftPatternPainter extends CustomPainter {
  final String seed;
  const _SoftPatternPainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final base = seed.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0xFFFFFF);
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.28);

    var n = base;
    for (var i = 0; i < 7; i++) {
      // Cheap deterministic pseudo-random: good enough for decoration and
      // avoids pulling in a Random instance per repaint.
      n = (n * 1103515245 + 12345) & 0x7FFFFFFF;
      final x = (n % 1000) / 1000 * size.width;
      n = (n * 1103515245 + 12345) & 0x7FFFFFFF;
      final y = (n % 1000) / 1000 * size.height;
      n = (n * 1103515245 + 12345) & 0x7FFFFFFF;
      final r = 40 + (n % 90).toDouble();
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SoftPatternPainter old) => old.seed != seed;
}
