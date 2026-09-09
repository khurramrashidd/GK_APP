import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/features_provider.dart';
import '../providers/auth_provider.dart';

class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lbAsync = ref.watch(leaderboardProvider);
    final myUid = ref.watch(profileProvider)?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard')),
      body: lbAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No scores yet.\nFinish a quiz to get on the board!',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          // Find my rank for the share button.
          final myIndex = myUid == null
              ? -1
              : entries.indexWhere((e) => e['uid'] == myUid);

          return Column(
            children: [
              if (myIndex >= 0)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Card(
                    color: theme.colorScheme.primaryContainer,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primary,
                        child: Text('#${myIndex + 1}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ),
                      title: const Text('Your rank',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          '${entries[myIndex]['totalScore']} points'),
                      trailing: IconButton(
                        icon: const Icon(Icons.share_rounded),
                        onPressed: () {
                          final score = entries[myIndex]['totalScore'];
                          SharePlus.instance.share(ShareParams(
                            text:
                                'I\'m ranked #${myIndex + 1} on GK Quiz Hero with '
                                '$score points! Can you beat me? 🎯',
                          ));
                        },
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    final isMe = e['uid'] == myUid;
                    final rank = i + 1;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      color: isMe ? theme.colorScheme.primaryContainer : null,
                      child: ListTile(
                        leading: _rankBadge(theme, rank),
                        title: Text(
                          e['displayName'] as String,
                          style: TextStyle(
                              fontWeight:
                                  isMe ? FontWeight.bold : FontWeight.normal),
                        ),
                        trailing: Text(
                          '${e['totalScore']}',
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _rankBadge(ThemeData theme, int rank) {
    final medal = switch (rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => null,
    };
    if (medal != null) {
      return Text(medal, style: const TextStyle(fontSize: 24));
    }
    return CircleAvatar(
      radius: 16,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      child: Text('$rank', style: theme.textTheme.bodySmall),
    );
  }
}
