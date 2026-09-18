import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/domain_model.dart';
import '../../data/models/question_model.dart';
import '../providers/database_provider.dart';
import '../providers/auth_provider.dart';
import 'multiplayer_waiting_screen.dart';

/// Entry point for 1v1 battles: pick what content to battle on, then either
/// create a match and share its invite code, find a random open opponent, or
/// join a specific match someone else shared with you.
class MultiplayerSetupScreen extends ConsumerStatefulWidget {
  const MultiplayerSetupScreen({super.key});

  @override
  ConsumerState<MultiplayerSetupScreen> createState() =>
      _MultiplayerSetupScreenState();
}

class _MultiplayerSetupScreenState extends ConsumerState<MultiplayerSetupScreen> {
  DomainModel? _domain;
  SubjectModel? _subject;
  SubLevelModel? _subLevel;
  bool _busy = false;
  final _codeCtrl = TextEditingController();

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _playerName() {
    final p = ref.read(profileProvider);
    if (p == null) return 'Player';
    return p.name.isNotEmpty ? p.name : p.displayName;
  }

  Future<List<String>> _buildQuestionIds() async {
    final repo = ref.read(questionRepositoryProvider);
    final List<QuestionModel> pool;
    if (_subject!.isShared) {
      // Shared subject: one pool across every domain that shares it.
      pool = await repo.getSharedSubjectQuestions(_subject!.id,
          subLevelId: _subLevel?.id);
    } else {
      await repo.ensureDomainSynced(_domain!.id);
      pool = await repo.getQuestions(_domain!.id, _subject!.id,
          subLevelId: _subLevel?.id);
    }
    if (pool.length < 4) {
      throw Exception('Not enough questions in this subject yet for a match.');
    }
    final shuffled = List<QuestionModel>.from(pool)..shuffle();
    return shuffled.take(10).map((q) => q.id).toList();
  }

  Future<void> _goToWaiting(String matchId) async {
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MultiplayerWaitingScreen(matchId: matchId)));
  }

  Future<void> _createAndInvite() async {
    if (_domain == null || _subject == null) {
      _snack('Pick a domain and subject first.');
      return;
    }
    final profile = ref.read(profileProvider);
    if (profile == null) return;
    setState(() => _busy = true);
    try {
      final ids = await _buildQuestionIds();
      final matchId = await ref.read(firestoreServiceProvider).createMatch(
            uid: profile.uid,
            playerName: _playerName(),
            domainId: _domain!.id,
            domainName: _domain!.name,
            subjectId: _subject!.id,
            subjectName: _subject!.name,
            subLevelId: _subLevel?.id,
            subLevelName: _subLevel?.name,
            questionIds: ids,
          );
      await _goToWaiting(matchId);
    } catch (e) {
      _snack('Could not create match: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _findRandom() async {
    if (_domain == null || _subject == null) {
      _snack('Pick a domain and subject first.');
      return;
    }
    final profile = ref.read(profileProvider);
    if (profile == null) return;
    setState(() => _busy = true);
    try {
      final ids = await _buildQuestionIds();
      final matchId =
          await ref.read(firestoreServiceProvider).findOrCreateRandomMatch(
                uid: profile.uid,
                playerName: _playerName(),
                domainId: _domain!.id,
                domainName: _domain!.name,
                subjectId: _subject!.id,
                subjectName: _subject!.name,
                subLevelId: _subLevel?.id,
                subLevelName: _subLevel?.name,
                questionIds: ids,
              );
      await _goToWaiting(matchId);
    } catch (e) {
      _snack('Could not find a match: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinByCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      _snack('Enter the 6-character code.');
      return;
    }
    final profile = ref.read(profileProvider);
    if (profile == null) return;
    setState(() => _busy = true);
    try {
      final matchId = await ref
          .read(firestoreServiceProvider)
          .joinMatchByCode(code, profile.uid, _playerName());
      if (matchId == null) {
        _snack('That code is invalid or already taken.');
        return;
      }
      await _goToWaiting(matchId);
    } catch (e) {
      _snack('Could not join: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final domainsAsync = ref.watch(domainsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('1v1 Quiz Battle')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Pick what to battle on', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                domainsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Error: $e'),
                  data: (domains) => Column(
                    children: [
                      DropdownButtonFormField<DomainModel>(
                        value: _domain,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Domain', border: OutlineInputBorder()),
                        items: domains
                            .map((d) =>
                                DropdownMenuItem(value: d, child: Text(d.name)))
                            .toList(),
                        onChanged: (d) => setState(() {
                          _domain = d;
                          _subject = null;
                          _subLevel = null;
                        }),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<SubjectModel>(
                        value: _subject,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Subject', border: OutlineInputBorder()),
                        items: (_domain?.subjects
                                    .where((s) => s.isActive)
                                    .toList() ??
                                const <SubjectModel>[])
                            .map((s) =>
                                DropdownMenuItem(value: s, child: Text(s.name)))
                            .toList(),
                        onChanged: (s) => setState(() {
                          _subject = s;
                          _subLevel = null;
                        }),
                      ),
                      if ((_subject?.subLevels
                                  .where((sl) => sl.isActive)
                                  .toList() ??
                              const <SubLevelModel>[])
                          .isNotEmpty) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<SubLevelModel>(
                          value: _subLevel,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Topic', border: OutlineInputBorder()),
                          items: _subject!.subLevels
                              .where((sl) => sl.isActive)
                              .map((sl) => DropdownMenuItem(
                                  value: sl, child: Text(sl.name)))
                              .toList(),
                          onChanged: (sl) => setState(() => _subLevel = sl),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52)),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Create match & invite a friend'),
                  onPressed: _createAndInvite,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52)),
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('Find a random opponent'),
                  onPressed: _findRandom,
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),
                Text('Have an invite code?', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _codeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: 'Enter code',
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: _joinByCode, child: const Text('Join')),
                  ],
                ),
              ],
            ),
    );
  }
}
