import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/attempt_stats_service.dart';

/// Lifetime breakdown of every question this device has seen: correct,
/// wrong, and still-skipped — drawn as a donut with a legend.
///
/// Drawn with a CustomPainter rather than a charting package: three arcs
/// don't justify another dependency to keep current and another thing that
/// can break a release build.
final attemptStatsProvider = FutureProvider<AttemptStats>((ref) async {
  return AttemptStatsService().stats();
});

class AttemptPieChart extends ConsumerWidget {
  /// Shown above the chart. Null hides the heading (for embedding).
  final String? title;
  const AttemptPieChart({super.key, this.title = 'Your question breakdown'});

  static const _correct = Color(0xFF2E7D32);
  static const _wrong = Color(0xFFC62828);
  static const _skipped = Color(0xFF9E9E9E);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(attemptStatsProvider);

    return async.when(
      loading: () => const SizedBox(
          height: 160, child: Center(child: CircularProgressIndicator())),
      error: (_, __) => const SizedBox.shrink(),
      data: (s) {
        if (s.seen == 0) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Icon(Icons.pie_chart_outline_rounded, color: theme.hintColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Finish a quiz and your breakdown appears here.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.hintColor),
                  ),
                ),
              ]),
            ),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),
                ],
                Row(
                  children: [
                    SizedBox(
                      width: 128,
                      height: 128,
                      child: CustomPaint(
                        painter: _DonutPainter(
                          values: [
                            s.correct.toDouble(),
                            s.wrong.toDouble(),
                            s.skipped.toDouble(),
                          ],
                          colors: const [_correct, _wrong, _skipped],
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('${s.accuracy.toStringAsFixed(0)}%',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold)),
                              Text('accuracy',
                                  style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _legend(theme, _correct, 'Correct', s.correct, s.seen),
                          _legend(theme, _wrong, 'Wrong', s.wrong, s.seen),
                          _legend(
                              theme, _skipped, 'Skipped', s.skipped, s.seen),
                          const Divider(height: 18),
                          Text('${s.attempted} attempted of ${s.seen} seen',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Answer a skipped question later and it moves out of '
                  'Skipped automatically. Counted on this device only.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _legend(
      ThemeData theme, Color c, String label, int value, int total) {
    final pct = total == 0 ? 0 : (value * 100 / total).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration:
                BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text('$value  ($pct%)', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  _DonutPainter({required this.values, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;

    final stroke = size.width * 0.20;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: (size.width - stroke) / 2,
    );

    var start = -math.pi / 2; // 12 o'clock
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweep = (values[i] / total) * 2 * math.pi;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = colors[i % colors.length],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.values != values;
}
