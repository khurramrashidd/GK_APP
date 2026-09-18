import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/content_update_model.dart';
import '../providers/auth_provider.dart';
import '../providers/database_provider.dart';

/// User-facing feed of newly added categories, subjects and question batches.
/// Opening it marks everything as seen, which clears the home badge.
class WhatsNewScreen extends ConsumerStatefulWidget {
  const WhatsNewScreen({super.key});

  @override
  ConsumerState<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends ConsumerState<WhatsNewScreen> {
  @override
  void initState() {
    super.initState();
    // Mark seen once the screen is up. Best-effort — failing just means the
    // badge stays, which is harmless.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final uid = ref.read(profileProvider)?.uid;
      if (uid == null) return;
      try {
        await ref.read(firestoreServiceProvider).markUpdatesSeen(uid);
        await ref.read(profileProvider.notifier).refresh();
      } catch (_) {}
    });
  }

  IconData _iconFor(String kind) {
    switch (kind) {
      case 'domain':
        return Icons.category_rounded;
      case 'subject':
        return Icons.menu_book_rounded;
      default:
        return Icons.add_circle_outline_rounded;
    }
  }

  String _ago(DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 30) return '${d.inDays}d ago';
    return '${(d.inDays / 30).floor()}mo ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(contentUpdatesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text("What's new")),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load updates.\n\n$e',
                textAlign: TextAlign.center),
          ),
        ),
        data: (List<ContentUpdateModel> items) {
          if (items.isEmpty) {
            return const Center(child: Text('Nothing new right now.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final u = items[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(_iconFor(u.kind),
                        color: theme.colorScheme.primary, size: 20),
                  ),
                  title: Text(u.title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    [
                      if (u.detail != null && u.detail!.isNotEmpty) u.detail!,
                      _ago(u.createdAt),
                    ].where((x) => x.isNotEmpty).join('\n'),
                  ),
                  isThreeLine:
                      u.detail != null && u.detail!.isNotEmpty,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
