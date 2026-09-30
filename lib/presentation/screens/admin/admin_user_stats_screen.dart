import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/user_profile.dart';
import '../../providers/database_provider.dart';

/// Admin > User statistics. Totals, gender split and state breakdown.
///
/// Charts are drawn with plain Flutter widgets rather than a charting
/// package: the shapes needed here are a ring and some bars, and adding a
/// dependency for that would mean another package to keep current and
/// another thing that can break a release build.
class AdminUserStatsScreen extends ConsumerWidget {
  const AdminUserStatsScreen({super.key});

  static const _palette = [
    Color(0xFF6A11CB),
    Color(0xFF2575FC),
    Color(0xFF11998E),
    Color(0xFFEB3349),
    Color(0xFFF7971E),
    Color(0xFF8E2DE2),
    Color(0xFF38EF7D),
    Color(0xFF4286F4),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(allUsersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('User statistics'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(allUsersProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load users.\n\n$e',
                textAlign: TextAlign.center),
          ),
        ),
        data: (users) => _body(context, theme, users),
      ),
    );
  }

  Widget _body(
      BuildContext context, ThemeData theme, List<UserProfile> users) {
    if (users.isEmpty) {
      return const Center(child: Text('No users yet.'));
    }

    final premium = users.where((u) => u.isPremium).length;
    final admins = users.where((u) => u.isAdminUser).length;

    // Gender — anything blank is grouped rather than dropped, so the totals
    // always add up to the real user count.
    final genderCounts = <String, int>{};
    for (final u in users) {
      final g = (u.gender ?? '').trim();
      final key = g.isEmpty ? 'Not specified' : g;
      genderCounts[key] = (genderCounts[key] ?? 0) + 1;
    }

    final stateCounts = <String, int>{};
    for (final u in users) {
      final st = u.state.trim();
      final key = st.isEmpty ? 'Not specified' : st;
      stateCounts[key] = (stateCounts[key] ?? 0) + 1;
    }
    final states = stateCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            _statCard(theme, 'Total users', '${users.length}',
                Icons.people_rounded),
            const SizedBox(width: 12),
            _statCard(
                theme, 'Premium', '$premium', Icons.workspace_premium_rounded),
            const SizedBox(width: 12),
            _statCard(theme, 'Admins', '$admins',
                Icons.admin_panel_settings_rounded),
          ],
        ),
        const SizedBox(height: 24),
        Text('Gender',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _donut(theme, genderCounts, users.length),
        const SizedBox(height: 28),
        Row(
          children: [
            Text('By state',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('${states.length} distinct',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor)),
          ],
        ),
        const SizedBox(height: 12),
        // Bars rather than a pie: with many states a pie becomes unreadable
        // slivers, while a sorted bar list stays scannable at any length.
        ...states.map((e) => _bar(theme, e.key, e.value, users.length)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _statCard(
      ThemeData theme, String label, String value, IconData icon) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(value,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Text(label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor)),
            ],
          ),
        ),
      ),
    );
  }

  /// Simple donut: stacked arc segments drawn with a CustomPainter, plus a
  /// legend. Kept small on purpose — it only ever shows a handful of slices.
  Widget _donut(ThemeData theme, Map<String, int> counts, int total) {
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Row(
      children: [
        SizedBox(
          width: 140,
          height: 140,
          child: CustomPaint(
            painter: _DonutPainter(
              values: [for (final e in entries) e.value.toDouble()],
              colors: [
                for (var i = 0; i < entries.length; i++)
                  _palette[i % _palette.length]
              ],
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$total',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text('users', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < entries.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _palette[i % _palette.length],
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(entries[i].key,
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                        '${entries[i].value}  '
                        '(${total == 0 ? 0 : (entries[i].value * 100 / total).round()}%)',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bar(ThemeData theme, String label, int value, int total) {
    final frac = total == 0 ? 0.0 : value / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 18,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text('$value (${(frac * 100).round()}%)',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.right),
          ),
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

    final stroke = size.width * 0.22;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: (size.width - stroke) / 2,
    );

    var start = -1.5708; // start at 12 o'clock
    for (var i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * 6.28319;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = colors[i % colors.length];
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.values != values || old.colors != colors;
}
