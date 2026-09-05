import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/suggestion_model.dart';
import '../../providers/database_provider.dart';

/// Admin > Suggestions. Review what users have asked for and respond.
/// Marking one "Added" is what tells the user it actually shipped.
class AdminSuggestionsScreen extends ConsumerWidget {
  const AdminSuggestionsScreen({super.key});

  Future<void> _respond(BuildContext context, WidgetRef ref,
      SuggestionModel s, String status) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(status == 'declined'
            ? 'Decline suggestion'
            : status == 'added'
                ? 'Mark as added'
                : 'Accept suggestion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('"${s.suggestedName}" — ${s.userEmail}'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Message to the user (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(firestoreServiceProvider).respondToSuggestion(
          s.id, status, ctrl.text.trim().isEmpty ? null : ctrl.text.trim());
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(allSuggestionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('User suggestions')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No suggestions yet.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final s = list[i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                                s.kind == 'domain' ? 'CATEGORY' : 'SUBJECT',
                                style: const TextStyle(fontSize: 10)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(s.suggestedName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(s.status.toUpperCase(),
                                style: const TextStyle(fontSize: 10)),
                          ),
                        ],
                      ),
                      if (s.parentDomainName != null &&
                          s.parentDomainName!.isNotEmpty)
                        Text('Under: ${s.parentDomainName}',
                            style: theme.textTheme.bodySmall),
                      if (s.note != null && s.note!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(s.note!, style: theme.textTheme.bodyMedium),
                      ],
                      const SizedBox(height: 4),
                      Text('From: ${s.userName} (${s.userEmail})',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor)),
                      if (s.adminResponse != null) ...[
                        const SizedBox(height: 4),
                        Text('Your reply: ${s.adminResponse}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontStyle: FontStyle.italic)),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (s.status != 'accepted')
                            OutlinedButton(
                              onPressed: () =>
                                  _respond(context, ref, s, 'accepted'),
                              child: const Text('Accept'),
                            ),
                          if (s.status != 'added')
                            FilledButton(
                              onPressed: () =>
                                  _respond(context, ref, s, 'added'),
                              child: const Text('Mark added'),
                            ),
                          if (s.status != 'declined')
                            TextButton(
                              style: TextButton.styleFrom(
                                  foregroundColor: theme.colorScheme.error),
                              onPressed: () =>
                                  _respond(context, ref, s, 'declined'),
                              child: const Text('Decline'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
