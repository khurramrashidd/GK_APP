import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/suggestion_model.dart';
import '../providers/auth_provider.dart';
import '../providers/database_provider.dart';

/// User-facing: suggest a new domain or subject, and see what happened to
/// past suggestions. Outcomes appear here (in-app), no push notifications.
class SuggestionsScreen extends ConsumerStatefulWidget {
  const SuggestionsScreen({super.key});

  @override
  ConsumerState<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends ConsumerState<SuggestionsScreen> {
  final _nameCtrl = TextEditingController();
  final _parentCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _kind = 'subject';
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _parentCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final profile = ref.read(profileProvider);
    if (profile == null) return;
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a name for your suggestion.')));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(firestoreServiceProvider).submitSuggestion(SuggestionModel(
            id: '',
            userUid: profile.uid,
            userName: profile.name.isNotEmpty
                ? profile.name
                : profile.displayName,
            userEmail: profile.email,
            kind: _kind,
            suggestedName: _nameCtrl.text.trim(),
            parentDomainName:
                _kind == 'subject' ? _parentCtrl.text.trim() : null,
            note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          ));
      _nameCtrl.clear();
      _parentCtrl.clear();
      _noteCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Thanks! Your suggestion has been sent.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not send: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  (Color, IconData, String) _statusVisual(String status, ThemeData theme) {
    switch (status) {
      case 'accepted':
        return (Colors.green, Icons.check_circle_rounded, 'Accepted');
      case 'added':
        return (Colors.blue, Icons.auto_awesome_rounded, 'Added to app');
      case 'declined':
        return (Colors.red, Icons.cancel_rounded, 'Not added');
      default:
        return (theme.hintColor, Icons.hourglass_empty_rounded, 'Pending');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = ref.watch(mySuggestionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Suggest content')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Missing something?',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Text(
              'Tell us what category or subject you would like to see. '
              'We review every suggestion.',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'subject', label: Text('Subject')),
              ButtonSegment(value: 'domain', label: Text('Category')),
            ],
            selected: {_kind},
            onSelectionChanged: (v) => setState(() => _kind = v.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText:
                  _kind == 'domain' ? 'Category name' : 'Subject name',
              border: const OutlineInputBorder(),
            ),
          ),
          if (_kind == 'subject') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _parentCtrl,
              decoration: const InputDecoration(
                labelText: 'Which category should it go under?',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Anything else? (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52)),
            icon: const Icon(Icons.send_rounded),
            label: const Text('Send suggestion'),
            onPressed: _busy ? null : _submit,
          ),
          const SizedBox(height: 28),
          Text('Your suggestions',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          mine.when(
            loading: () =>
                const Center(child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator())),
            error: (e, _) => Text('Error: $e'),
            data: (list) {
              if (list.isEmpty) {
                return Text('Nothing yet.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor));
              }
              return Column(
                children: [
                  for (final s in list)
                    Card(
                      child: ListTile(
                        onTap: s.isResolved && !s.seenByUser
                            ? () => ref
                                .read(firestoreServiceProvider)
                                .markSuggestionSeen(s.id)
                            : null,
                        leading: Builder(builder: (_) {
                          final (c, icon, _) =
                              _statusVisual(s.status, theme);
                          return Icon(icon, color: c);
                        }),
                        title: Text(s.suggestedName),
                        subtitle: Text(
                          '${s.kind == 'domain' ? 'Category' : 'Subject'}'
                          '${s.parentDomainName != null && s.parentDomainName!.isNotEmpty ? ' in ${s.parentDomainName}' : ''}'
                          '\n${_statusVisual(s.status, theme).$3}'
                          '${s.adminResponse != null ? ' — ${s.adminResponse}' : ''}',
                        ),
                        isThreeLine: true,
                        trailing: (s.isResolved && !s.seenByUser)
                            ? Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle),
                              )
                            : null,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
