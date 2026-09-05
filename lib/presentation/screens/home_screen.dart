import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/domain_model.dart';
import '../../data/models/user_profile.dart';
import '../providers/auth_provider.dart';
import '../providers/database_provider.dart';
import '../providers/reports_provider.dart';
import 'subject_screen.dart';
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
import '../../core/constants/app_constants.dart';
import 'admin/admin_home_screen.dart';
import '../widgets/user_avatar.dart';
import '../providers/features_provider.dart';

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
      // Big, always-available Play button — the primary action, like the
      // green Play button in Chess.com. Goes straight to the custom/random
      // quiz builder.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CustomQuizScreen())),
        icon: const Icon(Icons.play_arrow_rounded, size: 28),
        label: const Text('Play',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: RefreshIndicator(
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
class _DomainList extends StatefulWidget {
  final List<DomainModel> domains;
  const _DomainList({required this.domains});

  @override
  State<_DomainList> createState() => _DomainListState();
}

class _DomainListState extends State<_DomainList> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

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

    final all = List<DomainModel>.from(widget.domains)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
                Card(
                  elevation: 0,
                  color: cs.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Icon(Icons.bolt, size: 40, color: cs.primary),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Welcome Back!',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                            Text('Pick a domain, then a subject to begin.',
                                style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search domains or subjects...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                ),
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
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: colour.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(icon, color: colour, size: 26),
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

  /// Asks for location and stores it. Entirely optional: declining just
  /// leaves the date/time row hidden and shows an "Enable location" action
  /// the user can tap later.
  Future<void> _enableLocation() async {
    setState(() => _locBusy = true);
    try {
      final result = await LocationService().requestAndResolve();
      if (!result.granted) {
        if (mounted) {
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
    final streak = profile?.currentStreak ?? 0;
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
                    Row(
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
                      ],
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
                  _item(context, Icons.bookmark_rounded, 'Saved Questions', () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const BookmarksScreen()));
                  }),
                  _item(context, Icons.history_rounded, 'History & Stats', () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const HistoryScreen()));
                  }),
                  _item(context, Icons.leaderboard_rounded, 'Leaderboard', () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const LeaderboardScreen()));
                  }),
                  _item(context, Icons.sports_esports_rounded, '1v1 Quiz Battle',
                      () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const MultiplayerSetupScreen()));
                  }),
                  _item(context, Icons.search_rounded, 'Search', () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const SearchScreen()));
                  }),
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
