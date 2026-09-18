import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/domain_model.dart';
import '../../../data/models/recycle_bin_model.dart';
import '../../providers/database_provider.dart';

/// Admin > Recycle bin. Deleted domains, subjects and sub-levels land here
/// instead of vanishing, and can be restored to where they came from.
/// Removing an item from the bin is the only permanent delete.
class AdminRecycleBinScreen extends ConsumerStatefulWidget {
  const AdminRecycleBinScreen({super.key});

  @override
  ConsumerState<AdminRecycleBinScreen> createState() =>
      _AdminRecycleBinScreenState();
}

class _AdminRecycleBinScreenState
    extends ConsumerState<AdminRecycleBinScreen> {
  bool _busy = false;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Puts an item back where it came from.
  ///
  /// Restores are conservative: if something with the same id already exists
  /// at the destination (e.g. it was recreated by hand after deletion), the
  /// restore is refused rather than silently overwriting the newer version.
  Future<void> _restore(RecycleBinItem item) async {
    setState(() => _busy = true);
    try {
      final fs = ref.read(firestoreServiceProvider);
      final domains = await fs.fetchAllDomainsForAdmin();

      switch (item.type) {
        case 'domain':
          final restored = DomainModel.fromMap(item.payload);
          if (domains.any((d) => d.id == restored.id)) {
            _snack('A domain with id "${restored.id}" already exists.');
            return;
          }
          await fs.createOrUpdateDomain(restored);
          break;

        case 'subject':
          final parentMatches =
              domains.where((d) => d.id == item.parentDomainId).toList();
          if (parentMatches.isEmpty) {
            _snack('Its domain "${item.parentDomainName}" no longer exists. '
                'Restore that first.');
            return;
          }
          final parent = parentMatches.first;
          final restored = SubjectModel.fromMap(item.payload);
          if (parent.subjects.any((s) => s.id == restored.id)) {
            _snack('"${restored.name}" already exists in ${parent.name}.');
            return;
          }
          await fs.createOrUpdateDomain(
              parent.copyWith(subjects: [...parent.subjects, restored]));
          break;

        case 'subLevel':
          final dMatches =
              domains.where((d) => d.id == item.parentDomainId).toList();
          if (dMatches.isEmpty) {
            _snack('Its domain no longer exists. Restore that first.');
            return;
          }
          final parentDomain = dMatches.first;
          final sMatches = parentDomain.subjects
              .where((s) => s.id == item.parentSubjectId)
              .toList();
          if (sMatches.isEmpty) {
            _snack('Its subject "${item.parentSubjectName}" no longer exists. '
                'Restore that first.');
            return;
          }
          final parentSubject = sMatches.first;
          final restored = SubLevelModel.fromMap(item.payload);
          if (parentSubject.subLevels.any((x) => x.id == restored.id)) {
            _snack('"${restored.name}" already exists there.');
            return;
          }
          final updatedSubject = parentSubject
              .copyWith(subLevels: [...parentSubject.subLevels, restored]);
          await fs.createOrUpdateDomain(parentDomain.copyWith(
            subjects: [
              for (final s in parentDomain.subjects)
                if (s.id == updatedSubject.id) updatedSubject else s
            ],
          ));
          break;

        default:
          _snack('Unknown item type "${item.type}".');
          return;
      }

      await fs.removeFromRecycleBin(item.id);
      ref.invalidate(adminDomainsProvider);
      ref.invalidate(domainsProvider);
      _snack('"${item.name}" restored.');
    } catch (e) {
      _snack('Restore failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteForever(RecycleBinItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Permanently delete "${item.name}"?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(firestoreServiceProvider).removeFromRecycleBin(item.id);
    } catch (e) {
      _snack('Failed: $e');
    }
  }

  Future<void> _empty() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty recycle bin?'),
        content: const Text(
            'Everything in the bin is permanently deleted and can no longer '
            'be restored.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Empty bin'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(firestoreServiceProvider).emptyRecycleBin();
    } catch (e) {
      _snack('Failed: $e');
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'domain':
        return Icons.category_rounded;
      case 'subject':
        return Icons.menu_book_rounded;
      default:
        return Icons.label_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(recycleBinProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recycle bin'),
        actions: [
          IconButton(
            tooltip: 'Empty bin',
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: _busy ? null : _empty,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Error: $e', textAlign: TextAlign.center),
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const Center(
                      child: Text('Recycle bin is empty.'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final it = items[i];
                    return Card(
                      child: ListTile(
                        leading: Icon(_iconFor(it.type)),
                        title: Text(it.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '${it.locationLabel}'
                          '${it.deletedByEmail != null ? '\nby ${it.deletedByEmail}' : ''}'
                          '${it.deletedAt != null ? ' • ${it.deletedAt!.toLocal()}' : ''}',
                          style: theme.textTheme.bodySmall,
                        ),
                        isThreeLine: it.deletedByEmail != null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Restore',
                              icon: const Icon(Icons.restore_rounded),
                              onPressed: _busy ? null : () => _restore(it),
                            ),
                            IconButton(
                              tooltip: 'Delete forever',
                              icon: Icon(Icons.delete_forever_rounded,
                                  color: theme.colorScheme.error),
                              onPressed:
                                  _busy ? null : () => _deleteForever(it),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
