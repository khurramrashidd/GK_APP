import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../data/models/domain_model.dart';
import '../../providers/database_provider.dart';

/// Admin > Export. Dumps the question bank for a domain (or one subject
/// within it) as JSON — the same shape the bulk uploader accepts, so an
/// export can be re-imported or edited offline and re-uploaded.
class AdminExportScreen extends ConsumerStatefulWidget {
  const AdminExportScreen({super.key});

  @override
  ConsumerState<AdminExportScreen> createState() => _AdminExportScreenState();
}

class _AdminExportScreenState extends ConsumerState<AdminExportScreen> {
  DomainModel? _domain;
  SubjectModel? _subject;
  bool _busy = false;
  String? _preview;
  int _count = 0;

  Future<void> _export() async {
    if (_domain == null) return;
    setState(() {
      _busy = true;
      _preview = null;
    });
    try {
      final rows = await ref.read(firestoreServiceProvider).exportQuestions(
            domainId: _domain!.id,
            subjectId: _subject?.id,
          );
      const encoder = JsonEncoder.withIndent('  ');
      setState(() {
        _count = rows.length;
        _preview = encoder.convert(rows);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final domainsAsync = ref.watch(adminDomainsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Export questions')),
      body: domainsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (domains) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<DomainModel>(
              value: _domain,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Domain', border: OutlineInputBorder()),
              items: domains
                  .map((d) => DropdownMenuItem(value: d, child: Text(d.name)))
                  .toList(),
              onChanged: (d) => setState(() {
                _domain = d;
                _subject = null;
                _preview = null;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<SubjectModel?>(
              value: _subject,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Subject (leave empty for whole domain)',
                  border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem<SubjectModel?>(
                    value: null, child: Text('All subjects')),
                ...(_domain?.subjects ?? const <SubjectModel>[]).map(
                    (s) => DropdownMenuItem<SubjectModel?>(
                        value: s, child: Text(s.name))),
              ],
              onChanged: (s) => setState(() {
                _subject = s;
                _preview = null;
              }),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52)),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Generate JSON'),
              onPressed: (_domain == null || _busy) ? null : _export,
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_preview != null) ...[
              const SizedBox(height: 20),
              Text('$_count question(s) exported',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copy'),
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: _preview!));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('JSON copied to clipboard')));
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.share_rounded),
                      label: const Text('Share'),
                      onPressed: () => SharePlus.instance.share(ShareParams(
                        text: _preview!,
                        subject:
                            '${_domain!.name}${_subject != null ? ' - ${_subject!.name}' : ''} questions',
                      )),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  _preview!.length > 4000
                      ? '${_preview!.substring(0, 4000)}\n\n... (truncated in preview — Copy or Share gives the full file)'
                      : _preview!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
