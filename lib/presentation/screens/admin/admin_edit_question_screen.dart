import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/question_model.dart';
import '../../providers/database_provider.dart';

/// Loads one question fresh from Firestore by id and lets the admin edit it.
/// Saving bumps the domain version so the fix re-syncs to every device.
///
/// Returns `true` via Navigator.pop when a save succeeded, so the caller (the
/// reports screen) can offer to resolve the report in the same step.
class AdminEditQuestionScreen extends ConsumerStatefulWidget {
  final String questionId;
  const AdminEditQuestionScreen({super.key, required this.questionId});

  @override
  ConsumerState<AdminEditQuestionScreen> createState() =>
      _AdminEditQuestionScreenState();
}

class _AdminEditQuestionScreenState
    extends ConsumerState<AdminEditQuestionScreen> {
  QuestionModel? _q;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _questionCtrl = TextEditingController();
  final _explanationCtrl = TextEditingController();
  final List<TextEditingController> _optionCtrls = [];
  int _correctIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    _explanationCtrl.dispose();
    for (final c in _optionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final q = await ref
          .read(firestoreServiceProvider)
          .fetchQuestionById(widget.questionId);
      if (q == null) {
        setState(() {
          _loading = false;
          _error = 'This question no longer exists — it may have been deleted.';
        });
        return;
      }
      _questionCtrl.text = q.question;
      _explanationCtrl.text = q.explanation;
      for (final opt in q.options) {
        _optionCtrls.add(TextEditingController(text: opt));
      }
      _correctIndex = q.correctOptionIndex.clamp(0, q.options.length - 1);
      setState(() {
        _q = q;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not load: $e';
      });
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _save() async {
    final q = _q!;
    final question = _questionCtrl.text.trim();
    final options =
        _optionCtrls.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();

    if (question.isEmpty) {
      _snack('Question text cannot be empty.');
      return;
    }
    if (options.length < 2) {
      _snack('Need at least 2 non-empty options.');
      return;
    }
    if (_correctIndex >= options.length) {
      _snack('The correct answer points past the last option — fix it.');
      return;
    }

    setState(() => _saving = true);
    try {
      final newVersion =
          await ref.read(firestoreServiceProvider).updateQuestionAndBump(
        questionId: q.id,
        domainId: q.domainId,
        currentDomainVersion: await _currentDomainVersion(q.domainId),
        fields: {
          'question': question,
          'options': options,
          'correctOptionIndex': _correctIndex,
          'explanation': _explanationCtrl.text.trim(),
        },
      );
      // Refresh browse data so the admin's own device shows the edit.
      ref.invalidate(domainsProvider);
      ref.invalidate(adminDomainsProvider);
      _snack('Saved — will re-sync to users (domain now v$newVersion).');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _snack('Save failed: $e');
      setState(() => _saving = false);
    }
  }

  Future<int> _currentDomainVersion(String domainId) async {
    // Read the freshest version so concurrent edits don't collide on a stale one.
    return await ref.read(firestoreServiceProvider).fetchDomainVersion(domainId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit question')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text(_error!)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_q!.domainName} • ${_q!.subjectName}'
                        '${_q!.subLevelName != null ? ' • ${_q!.subLevelName}' : ''}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.hintColor),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _questionCtrl,
                        maxLines: null,
                        decoration: const InputDecoration(
                          labelText: 'Question',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Options (tap the circle to mark the correct one)',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _optionCtrls.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  i == _correctIndex
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  color: i == _correctIndex
                                      ? Colors.green
                                      : theme.hintColor,
                                ),
                                onPressed: () =>
                                    setState(() => _correctIndex = i),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _optionCtrls[i],
                                  decoration: InputDecoration(
                                    labelText: 'Option ${i + 1}'
                                        '${i == _correctIndex ? '  (correct)' : ''}',
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _explanationCtrl,
                        maxLines: null,
                        decoration: const InputDecoration(
                          labelText: 'Explanation (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 52)),
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.save_rounded),
                        label: Text(_saving ? 'Saving...' : 'Save & re-sync'),
                        onPressed: _saving ? null : _save,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Saving bumps the version so users who already downloaded '
                        'this question get the corrected version automatically.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.hintColor),
                      ),
                    ],
                  ),
                ),
    );
  }
}
