import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/friend_models.dart';
import '../../data/models/user_profile.dart';
import '../providers/auth_provider.dart';
import '../providers/database_provider.dart';

/// Friends: your list, incoming requests, and search by username.
///
/// Three tabs rather than one long screen so each job is one glance:
/// who you know, who wants to know you, and finding someone new.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _searchCtrl = TextEditingController();

  /// Debounce timer. Each keystroke would otherwise fire two Firestore
  /// queries; typing "khurram" would cost 14 reads. 350ms means one search
  /// per pause, not per letter.
  Timer? _debounce;
  List<({String uid, String username, String displayName})> _results = [];
  bool _searching = false;
  bool _searched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Called on every keystroke; actually searches once typing pauses.
  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      // One letter matches half the database and teaches nothing.
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _searched = true;
    });
    try {
      final me = ref.read(profileProvider)?.uid;
      final found =
          await ref.read(firestoreServiceProvider).searchUsersByUsername(q);
      if (mounted) {
        // Never show yourself in results — you can't befriend yourself.
        setState(() => _results = found.where((u) => u.uid != me).toList());
      }
    } catch (e) {
      _snack('Search failed: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _sendRequest(
      ({String uid, String username, String displayName}) target) async {
    final me = ref.read(profileProvider);
    if (me == null) return;
    if ((me.username ?? '').isEmpty) {
      _snack('Choose your own username first (Profile → Choose a username).');
      return;
    }
    try {
      await ref.read(firestoreServiceProvider).sendFriendRequest(
            toUid: target.uid,
            fromUid: me.uid,
            fromUsername: me.username!,
            fromName: me.name,
          );
      _snack('Request sent to @${target.username}');
    } on StateError catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Could not send request: $e');
    }
  }

  Future<void> _accept(FriendRequestModel r) async {
    final me = ref.read(profileProvider);
    if (me == null) return;
    try {
      await ref.read(firestoreServiceProvider).acceptFriendRequest(
            myUid: me.uid,
            myUsername: me.username ?? '',
            myName: me.name,
            request: r,
          );
      _snack('You are now friends with @${r.fromUsername}');
    } catch (e) {
      _snack('Could not accept: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profileProvider);
    final requests = ref.watch(friendRequestsProvider).valueOrNull ?? const [];

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Friends'),
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Friends'),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Requests'),
                    if (requests.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      CircleAvatar(
                        radius: 9,
                        backgroundColor: Theme.of(context).colorScheme.error,
                        child: Text('${requests.length}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white)),
                      ),
                    ],
                  ],
                ),
              ),
              const Tab(text: 'Find'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _friendsTab(me),
            _requestsTab(requests),
            _findTab(),
          ],
        ),
      ),
    );
  }

  // ------------------------------- Friends ---------------------------------

  Widget _friendsTab(UserProfile? me) {
    final theme = Theme.of(context);
    final async = ref.watch(friendsProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load friends.\n\n$e',
              textAlign: TextAlign.center),
        ),
      ),
      data: (friends) {
        if (friends.isEmpty) {
          return _empty(
            Icons.group_outlined,
            'No friends yet',
            'Use the Find tab to search for someone by their username.',
          );
        }
        // Most active first — the point of the list is encouragement.
        final sorted = List<FriendModel>.from(friends)
          ..sort((a, b) => b.questionsAnswered.compareTo(a.questionsAnswered));

        return RefreshIndicator(
          onRefresh: () async {
            if (me == null) return;
            await ref
                .read(firestoreServiceProvider)
                .refreshFriendActivity(me.uid, friends);
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: sorted.length,
            itemBuilder: (context, i) {
              final f = sorted[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      (f.displayName.isNotEmpty ? f.displayName : f.username)
                          .characters
                          .first
                          .toUpperCase(),
                      style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(
                      f.displayName.isNotEmpty ? f.displayName : '@${f.username}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    '@${f.username}\n'
                    '${f.questionsAnswered} questions answered'
                    '${f.currentStreak > 0 ? '  •  🔥 ${f.currentStreak} day streak' : ''}',
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'remove' && me != null) {
                        await ref
                            .read(firestoreServiceProvider)
                            .removeFriend(me.uid, f.uid);
                        _snack('Removed @${f.username}');
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'remove', child: Text('Remove friend')),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ------------------------------ Requests ---------------------------------

  Widget _requestsTab(List<FriendRequestModel> requests) {
    if (requests.isEmpty) {
      return _empty(Icons.mark_email_unread_outlined, 'No requests',
          'When someone adds you, their request appears here.');
    }
    final me = ref.read(profileProvider);
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: requests.length,
      itemBuilder: (context, i) {
        final r = requests[i];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_add_alt_1)),
            title: Text(r.fromName.isNotEmpty ? r.fromName : '@${r.fromUsername}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('@${r.fromUsername}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Decline',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: me == null
                      ? null
                      : () => ref
                          .read(firestoreServiceProvider)
                          .declineFriendRequest(me.uid, r.fromUid),
                ),
                IconButton(
                  tooltip: 'Accept',
                  icon: const Icon(Icons.check_circle_rounded),
                  color: Colors.green,
                  onPressed: () => _accept(r),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // -------------------------------- Find -----------------------------------

  Widget _findTab() {
    final friends = ref.watch(friendsProvider).valueOrNull ?? const [];
    final friendUids = friends.map((f) => f.uid).toSet();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            onChanged: _onQueryChanged,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Search by name or username',
              border: const OutlineInputBorder(),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {
                          _results = [];
                          _searched = false;
                        });
                      },
                    ),
            ),
          ),
        ),
        if (_searching) const LinearProgressIndicator(),
        Expanded(
          child: !_searched
              ? _empty(Icons.search_rounded, 'Find people',
                  'Type a username and search. Usernames are set in Profile.')
              : _results.isEmpty
                  ? _empty(Icons.person_off_outlined, 'Nobody found',
                      'No user matches that username.')
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _results.length,
                      itemBuilder: (context, i) {
                        final u = _results[i];
                        final already = friendUids.contains(u.uid);
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                                child: Icon(Icons.person_outline)),
                            title: Text('@${u.username}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(u.displayName),
                            trailing: already
                                ? const Chip(label: Text('Friend'))
                                : FilledButton.icon(
                                    icon: const Icon(Icons.person_add_alt_1,
                                        size: 18),
                                    label: const Text('Add'),
                                    onPressed: () => _sendRequest(u),
                                  ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _empty(IconData icon, String title, String body) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.hintColor),
            const SizedBox(height: 14),
            Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor)),
          ],
        ),
      ),
    );
  }
}
