import 'dart:async';
import 'package:flutter/material.dart';

/// Countdown timer for a single question.
///
/// Self-contained on purpose: QuizScreen is a stateless ConsumerWidget, and
/// converting it to stateful just to hold a ticker would touch a lot of
/// working code. Instead, give this widget a ValueKey(question.id) — Flutter
/// then rebuilds it from scratch on every new question, which resets the
/// countdown automatically with no manual bookkeeping.
class QuestionTimer extends StatefulWidget {
  final int seconds;
  final VoidCallback onTimeout;

  /// Paused once the answer is revealed/locked, so the countdown doesn't keep
  /// running while the user reads the explanation.
  final bool paused;

  const QuestionTimer({
    super.key,
    required this.seconds,
    required this.onTimeout,
    this.paused = false,
  });

  @override
  State<QuestionTimer> createState() => _QuestionTimerState();
}

class _QuestionTimerState extends State<QuestionTimer> {
  late int _left;
  Timer? _ticker;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _left = widget.seconds;
    _start();
  }

  void _start() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (widget.paused) return; // hold the clock, don't cancel it
      setState(() => _left--);
      if (_left <= 0) {
        t.cancel();
        // Guard against firing twice if a rebuild races the last tick.
        if (!_fired) {
          _fired = true;
          // Defer so we never call back during a build phase.
          WidgetsBinding.instance
              .addPostFrameCallback((_) => widget.onTimeout());
        }
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final urgent = _left <= 5;
    final frac = widget.seconds == 0 ? 0.0 : (_left / widget.seconds).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              value: frac,
              strokeWidth: 3,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(
                  urgent ? theme.colorScheme.error : theme.colorScheme.primary),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${_left < 0 ? 0 : _left}s',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: urgent ? theme.colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}
