import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/domain_model.dart';
import '../../providers/database_provider.dart';

/// Admin > Create structure from JSON.
///
/// Builds domains, subjects and sub-levels in bulk from one pasted/uploaded
/// JSON document — the fast way to lay out a new section rather than tapping
/// "New domain" then "Add subject" dozens of times.
///
/// Deliberately additive and non-destructive: existing domains keep their
/// settings and existing subjects are left alone. Nothing is renamed,
/// re-hidden or deleted by this screen.
class AdminStructureUploadScreen extends ConsumerStatefulWidget {
  const AdminStructureUploadScreen({super.key});

  @override
  ConsumerState<AdminStructureUploadScreen> createState() =>
      _AdminStructureUploadScreenState();
}

class _AdminStructureUploadScreenState
    extends ConsumerState<AdminStructureUploadScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  bool _createVisible = false;
  final List<String> _log = [];

  static const _sample = '''[
  {
    "domain": "India",
    "description": "Everything about India — states, history, culture.",
    "subjects": [
      { "name": "Indian States", "subLevels": ["Maharashtra", "Kerala", "Punjab"] },
      { "name": "Indian History", "description": "Ancient to modern India." },
      { "name": "Indian Polity" }
    ]
  },
  {
    "domain": "Space",
    "subLevelLabel": "Mission",
    "subjects": [
      { "name": "ISRO", "subLevels": ["Chandrayaan", "Mangalyaan"] },
      { "name": "NASA" }
    ]
  }
]''';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _say(String s) => setState(() => _log.add(s));

  static String slugify(String input) {
    final lower = input.toLowerCase().trim();
    return lower
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _log.clear();
    });
    try {
      final decoded = jsonDecode(_ctrl.text);
      if (decoded is! List) {
        _say('ERROR: the top level must be a JSON array [ ... ].');
        return;
      }

      final fs = ref.read(firestoreServiceProvider);
      final existing = await fs.fetchAllDomainsForAdmin();
      final byId = {for (final d in existing) d.id: d};

      var newDomains = 0, newSubjects = 0, newLevels = 0, skipped = 0;

      for (final rawEntry in decoded) {
        if (rawEntry is! Map) {
          skipped++;
          continue;
        }
        final entry = Map<String, dynamic>.from(rawEntry);
        final domainName = (entry['domain'] ?? entry['name'] ?? '').toString().trim();
        if (domainName.isEmpty) {
          _say('SKIPPED an entry with no "domain" name.');
          skipped++;
          continue;
        }
        final domainId = slugify(domainName);

        var domain = byId[domainId];
        if (domain == null) {
          domain = DomainModel(
            id: domainId,
            name: domainName,
            isActive: _createVisible,
            subLevelLabel: (entry['subLevelLabel'] ?? '').toString().trim().isEmpty
                ? null
                : entry['subLevelLabel'].toString().trim(),
          );
          newDomains++;
          _say('+ domain "$domainName"');
        } else {
          _say('· domain "$domainName" already exists — adding into it');
        }

        // Build the subject list, keeping everything already there.
        final subjects = List<SubjectModel>.from(domain.subjects);
        final rawSubjects = entry['subjects'];
        if (rawSubjects is List) {
          for (final rawSub in rawSubjects) {
            String subName;
            List<String> levelNames = const [];
            String? subDescription;

            if (rawSub is String) {
              subName = rawSub.trim();
            } else if (rawSub is Map) {
              final m = Map<String, dynamic>.from(rawSub);
              subName = (m['name'] ?? m['subject'] ?? '').toString().trim();
              subDescription =
                  (m['description'] ?? '').toString().trim().isEmpty
                      ? null
                      : m['description'].toString().trim();
              final rawLevels = m['subLevels'];
              if (rawLevels is List) {
                levelNames = rawLevels.map((x) => x.toString().trim()).toList();
              }
            } else {
              continue;
            }
            if (subName.isEmpty) continue;

            final subId = slugify(subName);
            final atIndex = subjects.indexWhere((x) => x.id == subId);

            // Sub-levels for this subject, merged with any already present.
            SubjectModel built;
            if (atIndex >= 0) {
              final current = subjects[atIndex];
              final haveLevels = current.subLevels.map((l) => l.id).toSet();
              final added = <SubLevelModel>[];
              for (final ln in levelNames) {
                final lid = slugify(ln);
                if (ln.isEmpty || haveLevels.contains(lid)) continue;
                added.add(SubLevelModel(
                    id: lid, name: ln, isActive: _createVisible));
                newLevels++;
              }
              if (added.isEmpty) continue; // nothing new for this subject
              built = current
                  .copyWith(subLevels: [...current.subLevels, ...added]);
              subjects[atIndex] = built;
              _say('  + ${added.length} topic(s) under "$subName"');
            } else {
              final levels = <SubLevelModel>[];
              for (final ln in levelNames) {
                if (ln.isEmpty) continue;
                levels.add(SubLevelModel(
                    id: slugify(ln), name: ln, isActive: _createVisible));
                newLevels++;
              }
              built = SubjectModel(
                id: subId,
                name: subName,
                isActive: _createVisible,
                description: subDescription,
                subLevels: levels,
              );
              subjects.add(built);
              newSubjects++;
              _say('  + subject "$subName"'
                  '${levels.isEmpty ? '' : ' (${levels.length} topics)'}');
            }
          }
        }

        final updated = domain.copyWith(
          subjects: subjects,
          description: (entry['description'] ?? '').toString().trim().isEmpty
              ? domain.description
              : entry['description'].toString().trim(),
        );
        await fs.createOrUpdateDomain(updated);
        byId[domainId] = updated;
      }

      _say('');
      _say('DONE — $newDomains domain(s), $newSubjects subject(s), '
          '$newLevels topic(s) created.'
          '${skipped > 0 ? ' $skipped entry/entries skipped.' : ''}');
      if (!_createVisible) {
        _say('Everything was created HIDDEN. Unhide from Domains & Subjects '
            'when you are ready to show it.');
      }

      ref.invalidate(adminDomainsProvider);
      ref.invalidate(domainsProvider);
    } on FormatException catch (e) {
      _say('ERROR: that is not valid JSON.\n$e');
    } catch (e) {
      _say('ERROR: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Create structure from JSON')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Build domains and subjects in one go',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text(
                      'A subject can be a plain name, or an object with an '
                      'optional description and a list of sub-levels. '
                      'Existing domains and subjects are never overwritten — '
                      'only missing ones get added.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.article_outlined),
                  label: const Text('Insert sample'),
                  onPressed: _busy
                      ? null
                      : () => setState(() => _ctrl.text = _sample),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy sample'),
                  onPressed: () async {
                    await Clipboard.setData(
                        const ClipboardData(text: _sample));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Sample copied')));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            maxLines: 14,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Paste your JSON here...',
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _createVisible,
            onChanged:
                _busy ? null : (v) => setState(() => _createVisible = v),
            title: const Text('Create visible to users'),
            subtitle: const Text(
                'Off by default — new content is created hidden so users '
                'never see an empty category before you add questions.'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52)),
            icon: const Icon(Icons.playlist_add_rounded),
            label: const Text('Create structure'),
            onPressed: _busy ? null : _run,
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_log.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(_log.join('\n'),
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }
}
