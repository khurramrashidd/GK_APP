import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/domain_model.dart';
import '../../data/models/user_profile.dart';
import '../providers/auth_provider.dart';
import '../providers/database_provider.dart';
import '../providers/admin_prefs_provider.dart';
import '../providers/reports_provider.dart';
import 'subject_screen.dart';
import 'login_screen.dart';
import 'whats_new_screen.dart';
import 'privacy_screen.dart';
import 'friends_screen.dart';
import 'reels_quiz_screen.dart';
import '../widgets/daily_banner.dart';
import 'profile_screen.dart';
import 'my_reports_screen.dart';
import 'bookmarks_screen.dart';
import 'history_screen.dart';
import 'leaderboard_screen.dart';
import 'search_screen.dart';
import 'multiplayer_setup_screen.dart';
import 'about_screen.dart';
import 'custom_quiz_screen.dart';
import 'suggestions_screen.dart';
import 'terms_screen.dart';
import '../../services/location_service.dart';
import 'admin/admin_home_screen.dart';
import '../widgets/user_avatar.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final domainsAsync = ref.watch(domainsProvider);
    // Watch the profile itself so the admin button + avatar update as soon as
    // the profile loads (and if the photo/name changes later).
    final profile = ref.watch(profileProvider);
    final isAdmin = ref.read(profileProvider.notifier).isAdmin;

    final myReports = ref.watch(myReportsProvider).valueOrNull ?? const [];
    final unseenCount =
        myReports.where((r) => r.isResolved && !r.seenByReporter).length;

    return Scaffold(
      drawer: _AppDrawer(profile: profile, isAdmin: isAdmin),
      appBar: AppBar(
        title: Text(AppConstants.appName,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          // Lets a user opt out of (or into) reels mode regardless of the
          // admin default. Their choice is remembered.
          IconButton(
            tooltip: ref.watch(reelsModeActiveProvider)
                ? 'Switch to browse'
                : 'Switch to Reels',
            icon: Icon(ref.watch(reelsModeActiveProvider)
                ? Icons.grid_view_rounded
                : Icons.video_library_rounded),
            onPressed: () => ref
                .read(reelsUserChoiceProvider.notifier)
                .set(!ref.read(reelsModeActiveProvider)),
          ),
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SearchScreen())),
          ),
          IconButton(
            tooltip: 'My Reports',
            icon: Badge(
              isLabelVisible: unseenCount > 0,
              label: Text('$unseenCount'),
              child: const Icon(Icons.notifications_rounded),
            ),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MyReportsScreen())),
          ),
          IconButton(
            icon: UserAvatar(profile: profile, radius: 16),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
          const SizedBox(width: 4),
        ],
      ),
      // (app bar actions include the What's new bell, added below)
      // Big, always-available Play button — the primary action, like the
      // green Play button in Chess.com. Goes straight to the custom/random
      // quiz builder.
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Reels sits beside Play as a peer action, not buried in the menu.
          FloatingActionButton.extended(
            heroTag: 'fab_reels',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ReelsQuizScreen())),
            backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
            foregroundColor:
                Theme.of(context).colorScheme.onTertiaryContainer,
            icon: const Icon(Icons.video_library_rounded, size: 22),
            label: const Text('Reels',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'fab_play',
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CustomQuizScreen())),
            icon: const Icon(Icons.play_arrow_rounded, size: 28),
            label: const Text('Play',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      // When Reels is the active mode (admin default, unless the user chose
      // otherwise) the home body IS the reels feed. This is what the admin
      // switch was always meant to do — previously the flag was stored and
      // displayed but nothing user-facing ever read it.
      body: ref.watch(reelsModeActiveProvider)
          ? const ReelsQuizScreen(embedded: true)
          : RefreshIndicator(
        onRefresh: () async => ref.refresh(domainsProvider.future),
        child: domainsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => const _ErrorView(
            message:
                'Could not load quiz domains.\nCheck your connection and pull to retry.',
          ),
          data: (domains) => _DomainList(domains: domains),
        ),
      ),
    );
  }
}

/// Home = domains only. With ~30 domains each holding 10-50 subjects,
/// showing subjects here too would be an unusable wall; tapping a domain
/// opens SubjectScreen, which has its own search.
class _DomainList extends ConsumerStatefulWidget {
  final List<DomainModel> domains;
  const _DomainList({required this.domains});

  @override
  ConsumerState<_DomainList> createState() => _DomainListState();
}

class _DomainListState extends ConsumerState<_DomainList> {
  /// Build number whose update banner the user dismissed. Kept in memory
  /// only: a newer release gets a new number and shows again regardless.
  int? _dismissedUpdateBuild;


  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Full release notes, opened from the compact update banner.
  void _showUpdateDetails(AppUpdateInfo update) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final t = Theme.of(ctx);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Icon(Icons.system_update_rounded,
                      color: t.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      update.versionName.isEmpty
                          ? 'Update available'
                          : 'Version ${update.versionName}',
                      style: t.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  // Explicit close. The drag handle alone isn't obvious to
                  // everyone, and there's no app-bar back button on a sheet.
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ]),
                const SizedBox(height: 14),
                Text(update.notes ?? 'A newer version of the app is ready.',
                    style: t.textTheme.bodyMedium?.copyWith(height: 1.45)),
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50)),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download update'),
                  onPressed: () => launchUrl(Uri.parse(update.url),
                      mode: LaunchMode.externalApplication),
                ),
                if (!update.mandatory) ...[
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() =>
                          _dismissedUpdateBuild = update.buildNumber);
                    },
                    child: const Text('Not now'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Greeting, live stats and search in one block.
  ///
  /// Replaces a "Welcome Back!" card that used a full row to say nothing.
  /// The same space now carries the three numbers people actually open the
  /// app to see, so the header earns its height instead of decorating.
  Widget _heroHeader(ThemeData theme, UserProfile? profile) {
    final cs = theme.colorScheme;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final name = (profile?.name ?? '').trim();
    final first = name.isEmpty ? '' : name.split(' ').first;

    final answered = profile?.questionsAnswered ?? 0;
    final correct = profile?.correctAnswers ?? 0;
    final accuracy = answered == 0 ? 0 : (correct * 100 / answered).round();

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary, cs.primary.withValues(alpha: 0.72)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(first.isEmpty ? greeting : '$greeting, $first',
              style: TextStyle(
                  color: cs.onPrimary.withValues(alpha: 0.85), fontSize: 13)),
          const SizedBox(height: 2),
          Text('What will you learn today?',
              style: TextStyle(
                  color: cs.onPrimary,
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  height: 1.2)),
          const SizedBox(height: 16),

          // Three numbers, evenly weighted — the reason to come back.
          Row(
            children: [
              _statPill(cs, '🔥', '${profile?.displayStreak ?? 0}',
                  'day streak'),
              const SizedBox(width: 8),
              _statPill(cs, '🎯', '$accuracy%', 'accuracy'),
              const SizedBox(width: 8),
              _statPill(cs, '📚', '$answered', 'answered'),
            ],
          ),
          const SizedBox(height: 16),

          // Search sits ON the header rather than below it, so the top of
          // the screen is one block instead of three stacked boxes.
          Material(
            color: cs.onPrimary.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(color: cs.onPrimary, fontSize: 14),
              cursorColor: cs.onPrimary,
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: InputBorder.none,
                hintText: 'Search domains or subjects...',
                hintStyle:
                    TextStyle(color: cs.onPrimary.withValues(alpha: 0.7)),
                prefixIcon: Icon(Icons.search_rounded,
                    size: 20, color: cs.onPrimary.withValues(alpha: 0.9)),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.clear_rounded,
                            size: 18, color: cs.onPrimary),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (v) =>
                  setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statPill(ColorScheme cs, String emoji, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: cs.onPrimary.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            Text(label,
                style: TextStyle(
                    color: cs.onPrimary.withValues(alpha: 0.8), fontSize: 10)),
          ],
        ),
      ),
    );
  }

  /// Whether the signed-in account is an anonymous guest.
  bool get _isGuest => ref.read(authServiceProvider).isGuest;

  /// A stable per-domain icon+colour, picked from the name so a domain always
  /// looks the same without needing an icon field in the database.
  (IconData, Color) _visual(String name, ColorScheme cs) {
    const icons = [
      Icons.public_rounded,
      Icons.science_rounded,
      Icons.calculate_rounded,
      Icons.memory_rounded,
      Icons.sports_soccer_rounded,
      Icons.movie_rounded,
      Icons.music_note_rounded,
      Icons.menu_book_rounded,
      Icons.emoji_events_rounded,
      Icons.lightbulb_rounded,
      Icons.newspaper_rounded,
      Icons.account_balance_rounded,
      Icons.psychology_rounded,
      Icons.favorite_rounded,
      Icons.eco_rounded,
      Icons.translate_rounded,
      Icons.palette_rounded,
      Icons.rocket_launch_rounded,
      Icons.extension_rounded,
      Icons.directions_car_rounded,
      Icons.restaurant_rounded,
      Icons.people_rounded,
      Icons.gavel_rounded,
      Icons.school_rounded,
    ];
    final palette = [
      cs.primary,
      cs.secondary,
      cs.tertiary,
      Colors.teal,
      Colors.deepOrange,
      Colors.indigo,
      Colors.pink,
      Colors.green,
    ];
    final h = name.toLowerCase().codeUnits.fold<int>(0, (a, b) => a + b);
    return (icons[h % icons.length], palette[h % palette.length]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // Needed by the hero header: greeting name and the three stat pills.
    final profile = ref.watch(profileProvider);

    if (widget.domains.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Center(
              child: Text(
                  'No quiz domains yet.\nAdd some from the Admin panel.',
                  textAlign: TextAlign.center)),
        ],
      );
    }

    // Followed domains float to the top, then everything else alphabetically.
    final followed =
        ref.watch(profileProvider)?.followedDomains ?? const <String>[];
    final all = List<DomainModel>.from(widget.domains)
      ..sort((a, b) {
        final af = followed.contains(a.id) ? 0 : 1;
        final bf = followed.contains(b.id) ? 0 : 1;
        if (af != bf) return af - bf;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final domains = _query.isEmpty
        ? all
        : all.where((d) {
            // Match the domain name OR any of its subject names, so typing
            // "chemistry" surfaces the domain that contains it.
            if (d.name.toLowerCase().contains(_query)) return true;
            return d.subjects
                .any((s) => s.isActive && s.name.toLowerCase().contains(_query));
          }).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Update banner — shown when an admin has published a newer
                // build than this one. Dismissible per-version: dismissing
                // hides THIS version's banner only, so the next release
                // shows again. Mandatory updates can't be dismissed.
                Builder(builder: (_) {
                  final update = ref.watch(availableUpdateProvider);
                  if (update == null) return const SizedBox.shrink();
                  if (_dismissedUpdateBuild == update.buildNumber &&
                      !update.mandatory) {
                    return const SizedBox.shrink();
                  }
                  // ONE compact row. Release notes can run to a dozen lines,
                  // and inline they pushed the domain grid off the screen —
                  // so the detail lives in a sheet you open by tapping.
                  return Card(
                    color: cs.primaryContainer,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showUpdateDetails(update),
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(14, 10, 10, 10),
                        child: Row(
                          children: [
                            Icon(Icons.system_update_rounded,
                                color: cs.onPrimaryContainer, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Update available'
                                '${update.versionName.isEmpty ? '' : '  •  v${update.versionName}'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: cs.onPrimaryContainer),
                              ),
                            ),
                            Text('Details',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onPrimaryContainer)),
                            Icon(Icons.chevron_right_rounded,
                                color: cs.onPrimaryContainer),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),

                // Guests get a persistent (but dismissible-feeling, low-key)
                // nudge: an anonymous account is device-only and lost on
                // uninstall, so upgrading actually protects their progress.
                if (_isGuest)
                  Card(
                    elevation: 0,
                    color: cs.tertiaryContainer,
                    child: ListTile(
                      leading: Icon(Icons.person_outline_rounded,
                          color: cs.onTertiaryContainer),
                      title: Text('You are browsing as a guest',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: cs.onTertiaryContainer)),
                      subtitle: Text(
                        'Create a free account to keep your scores, streak '
                        'and bookmarks safe — guest progress is lost if the '
                        'app is uninstalled.',
                        style: TextStyle(color: cs.onTertiaryContainer),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const LoginScreen())),
                    ),
                  ),
                if (_isGuest) const SizedBox(height: 12),
                _heroHeader(theme, profile),
                // One-line quote directly under the hero: above the fold, so
                // it is actually seen, without pushing content down.
                const DailyBanner(mode: 'strip'),
                const SizedBox(height: 8),
                const DailyBanner(mode: 'pick'),
                const SizedBox(height: 16),
                Text(
                    _query.isEmpty
                        ? 'Domains'
                        : '${domains.length} result${domains.length == 1 ? '' : 's'}',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
        if (domains.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: Text('Nothing matches "$_query".')),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.05,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final d = domains[i];
                  final (icon, colour) = _visual(d.name, cs);
                  final subjectCount =
                      d.subjects.where((s) => s.isActive).length;
                  return Card(
                    elevation: 2,
                    clipBehavior: Clip.hardEdge,
                    child: InkWell(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => SubjectScreen(domain: d))),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: colour.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(icon, color: colour, size: 26),
                                ),
                                const Spacer(),
                                // Follow toggle — followed domains sort to
                                // the top of this grid.
                                InkWell(
                                  onTap: () => ref
                                      .read(profileProvider.notifier)
                                      .toggleFollowDomain(d.id),
                                  borderRadius: BorderRadius.circular(20),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      followed.contains(d.id)
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      size: 20,
                                      color: followed.contains(d.id)
                                          ? Colors.red
                                          : theme.hintColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Text(d.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(
                                '$subjectCount subject${subjectCount == 1 ? '' : 's'}',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: theme.hintColor)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                childCount: domains.length,
              ),
            ),
          ),

        // Quote last: it is a closing note, not a headline. Putting it above
        // the content pushed the domains below the fold for no benefit.
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: DailyBanner(mode: 'thought'),
          ),
        ),

        // Clears the floating Play / Reels buttons.
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.wifi_off_rounded, size: 60),
        const SizedBox(height: 16),
        Center(child: Text(message, textAlign: TextAlign.center)),
      ],
    );
  }
}

/// Modern side navigation drawer. Header shows the avatar + name; body links to
/// the personal and social features. Admin entry only shows for admins.
class _AppDrawer extends ConsumerStatefulWidget {
  final UserProfile? profile;
  final bool isAdmin;
  const _AppDrawer({required this.profile, required this.isAdmin});

  @override
  ConsumerState<_AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<_AppDrawer> {
  bool _locBusy = false;
  bool _triedAutoUpgrade = false;

  /// True when the stored place name is just "19.076, 72.878" — i.e. saved
  /// before city-name lookup existed, or saved while the lookup was failing.
  static bool _looksLikeCoordinates(String? name) {
    if (name == null) return false;
    // No regex: just check it parses as "<number>, <number>".
    final parts = name.split(',');
    if (parts.length != 2) return false;
    return double.tryParse(parts[0].trim()) != null &&
        double.tryParse(parts[1].trim()) != null;
  }

  @override
  void initState() {
    super.initState();
    // One silent attempt to replace a stale coordinate label with a real
    // city name. Runs once per drawer build, never prompts, and is a no-op
    // if permission was revoked or the lookup fails.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_triedAutoUpgrade) return;
      _triedAutoUpgrade = true;
      final p = widget.profile;
      if (p?.latitude != null && _looksLikeCoordinates(p?.locationName)) {
        _enableLocation(silent: true);
      }
    });
  }

  /// Asks for location and stores it. Entirely optional: declining just
  /// leaves the date/time row hidden and shows an "Enable location" action
  /// the user can tap later.
  Future<void> _enableLocation({bool silent = false}) async {
    setState(() => _locBusy = true);
    try {
      final result = await LocationService().requestAndResolve();
      if (!result.granted) {
        // A silent background refresh must never nag the user.
        if (mounted && !silent) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(result.error ??
                  'Location permission declined. You can enable it any time.')));
        }
        return;
      }
      await ref.read(profileProvider.notifier).saveLocation(
            latitude: result.latitude,
            longitude: result.longitude,
            locationName: result.placeName,
            timeZoneName: result.timeZoneName,
          );
    } finally {
      if (mounted) setState(() => _locBusy = false);
    }
  }

  String _formattedNow(String? zone) {
    final n = DateTime.now();
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final h = n.hour % 12 == 0 ? 12 : n.hour % 12;
    final ampm = n.hour < 12 ? 'AM' : 'PM';
    final mm = n.minute.toString().padLeft(2, '0');
    return '${n.day} ${months[n.month - 1]} ${n.year}, $h:$mm $ampm'
        '${zone != null && zone.isNotEmpty ? ' $zone' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final isAdmin = widget.isAdmin;
    final theme = Theme.of(context);
    // displayStreak, not currentStreak: the stored value is only rewritten
    // when a quiz finishes, so it would keep showing a streak already lost.
    final streak = profile?.displayStreak ?? 0;
    final name = (profile?.name.isNotEmpty ?? false)
        ? profile!.name
        : (profile?.displayName ?? 'Guest');
    final hasLocation = profile?.latitude != null;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: theme.colorScheme.primaryContainer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UserAvatar(profile: profile, radius: 32),
                  const SizedBox(height: 12),
                  Text(
                    name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (streak > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🔥', style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 4),
                          Text('$streak-day streak',
                              style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  // Local date/time + place — only when the user granted
                  // location. Optional throughout; declining costs nothing.
                  const SizedBox(height: 8),
                  if (hasLocation)
                    // Tappable so a stored location can be re-resolved. This
                    // matters because a location saved before city-name
                    // lookup existed holds a raw coordinate string, and
                    // without a refresh there'd be no way to upgrade it.
                    InkWell(
                      onTap: _locBusy ? null : _enableLocation,
                      child: Row(
                        children: [
                          Icon(Icons.place_rounded,
                              size: 14, color: theme.colorScheme.primary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${profile?.locationName ?? 'Your location'}\n'
                              '${_formattedNow(profile?.timeZoneName)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          if (_locBusy)
                            const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                          else
                            Icon(Icons.refresh_rounded,
                                size: 14, color: theme.hintColor),
                        ],
                      ),
                    )
                  else
                    TextButton.icon(
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact),
                      icon: _locBusy
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location_rounded, size: 16),
                      label: const Text('Enable location',
                          style: TextStyle(fontSize: 12)),
                      onPressed: _locBusy ? null : _enableLocation,
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _item(context, Icons.home_rounded, 'Home',
                      () => Navigator.pop(context)),
                  if (ref.watch(tabVisibleProvider('bookmarks')))
                  _item(context, Icons.bookmark_rounded, 'Saved Questions', () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const BookmarksScreen()));
                  }),
                  if (ref.watch(tabVisibleProvider('history')))
                  _item(context, Icons.history_rounded, 'History & Stats', () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const HistoryScreen()));
                  }),
                  // Always reachable: hiding "leaderboard" now hides only the
                  // Top Scores and Accuracy rankings INSIDE the screen, so
                  // the streaks board and personal pie chart stay available.
                  _item(context, Icons.leaderboard_rounded, 'Leaderboard', () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const LeaderboardScreen()));
                  }),
                  if (ref.watch(tabVisibleProvider('battle')))
                  _item(context, Icons.sports_esports_rounded, '1v1 Quiz Battle',
                      () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const MultiplayerSetupScreen()));
                  }),
                  if (ref.watch(tabVisibleProvider('search')))
                  _item(context, Icons.search_rounded, 'Search', () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const SearchScreen()));
                  }),
                  if (ref.watch(tabVisibleProvider('reports')))
                  _item(context, Icons.notifications_rounded, 'My Reports', () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const MyReportsScreen()));
                  }),
                  _item(context, Icons.person_rounded, 'Profile', () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ProfileScreen()));
                  }),
                  if (ref.watch(tabVisibleProvider('whatsNew')))
                  Builder(builder: (_) {
                    final unseen = ref.watch(unseenUpdateCountProvider);
                    return ListTile(
                      leading: Badge(
                        isLabelVisible: unseen > 0,
                        label: Text('$unseen'),
                        child: const Icon(Icons.campaign_outlined),
                      ),
                      title: const Text("What's new"),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const WhatsNewScreen()));
                      },
                    );
                  }),
                  if (ref.watch(tabVisibleProvider('friends')))
                  Builder(builder: (_) {
                    final pending =
                        ref.watch(friendRequestsProvider).valueOrNull?.length ?? 0;
                    return ListTile(
                      leading: Badge(
                        isLabelVisible: pending > 0,
                        label: Text('$pending'),
                        child: const Icon(Icons.group_outlined),
                      ),
                      title: const Text('Friends'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const FriendsScreen()));
                      },
                    );
                  }),
                  if (ref.watch(tabVisibleProvider('reels')))
                  _item(context, Icons.video_library_rounded, 'Reels mode',
                      () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ReelsQuizScreen()));
                  }),
                  if (ref.watch(tabVisibleProvider('suggestions')))
                  _item(context, Icons.privacy_tip_outlined, 'Your data', () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const PrivacyScreen()));
                  }),
                  _item(context, Icons.lightbulb_outline_rounded,
                      'Suggest content', () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const SuggestionsScreen()));
                  }),
                  const Divider(),
                  _item(context, Icons.description_outlined,
                      'Terms & Conditions', () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const TermsScreen(readOnly: true)));
                  }),
                  _item(context, Icons.info_outline_rounded, 'About', () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AboutScreen()));
                  }),
                  if (isAdmin) ...[
                    const Divider(),
                    _item(context, Icons.admin_panel_settings_rounded,
                        'Admin Panel', () {
                      Navigator.pop(context);
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const AdminHomeScreen()));
                    }),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext context, IconData icon, String label,
          VoidCallback onTap) =>
      ListTile(
        leading: Icon(icon),
        title: Text(label),
        onTap: onTap,
      );
}
