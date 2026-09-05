import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/models/match_model.dart';
import '../providers/multiplayer_provider.dart';
import '../providers/database_provider.dart';
import '../providers/auth_provider.dart';
import 'multiplayer_match_screen.dart';

/// Shown right after creating or joining a match. If it's already active
/// (you joined an open match), this screen shows almost instantly before
/// forwarding you in. If you're waiting for someone, it shows your invite
/// code and moves on automatically the moment someone joins — no polling,
/// the match stream just tells us.
class MultiplayerWaitingScreen extends ConsumerStatefulWidget {
  final String matchId;
  const MultiplayerWaitingScreen({super.key, required this.matchId});

  @override
  ConsumerState<MultiplayerWaitingScreen> createState() =>
      _MultiplayerWaitingScreenState();
}

class _MultiplayerWaitingScreenState
    extends ConsumerState<MultiplayerWaitingScreen> {
  bool _navigated = false;
  bool _cancelling = false;

  void _maybeGoToMatch(MatchModel match) {
    if (_navigated) return;
    if (match.isActive || match.isFinished) {
      final uid = ref.read(profileProvider)?.uid;
      final slot = uid != null ? match.slotFor(uid) : null;
      if (slot == null) return;
      _navigated = true;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) =>
            MultiplayerMatchScreen(matchId: widget.matchId, playerSlot: slot),
      ));
    }
  }

  Future<void> _cancel() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    try {
      await ref.read(firestoreServiceProvider).cancelWaitingMatch(widget.matchId);
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final matchAsync = ref.watch(matchStreamProvider(widget.matchId));
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _cancel();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Waiting for opponent')),
        body: matchAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (match) {
            if (match == null) {
              return const Center(child: Text('This match no longer exists.'));
            }
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _maybeGoToMatch(match));

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  Text('Waiting for someone to join...',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 24),
                  Text('Share this code with a friend:',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      match.inviteCode,
                      style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold, letterSpacing: 4),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Share code'),
                    onPressed: () => SharePlus.instance.share(ShareParams(
                        text:
                            'Join my quiz battle on GK Quiz Hero! Use code: ${match.inviteCode}')),
                  ),
                  const SizedBox(height: 32),
                  TextButton(
                    onPressed: _cancelling ? null : _cancel,
                    child: Text(_cancelling ? 'Cancelling...' : 'Cancel'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
