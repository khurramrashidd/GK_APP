import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/user_profile.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/attempt_pie_chart.dart';
import '../widgets/user_avatar.dart';
import 'login_screen.dart';

/// User dashboard + profile form.
/// Required: name, state.
/// Optional: dob, mobile, city, pincode, gender.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameCtrl   = TextEditingController();
  final _stateCtrl  = TextEditingController();
  final _dobCtrl    = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _cityCtrl   = TextEditingController();
  final _pinCtrl    = TextEditingController();

  // 'Prefer not to say' matters: gender is required so the admin charts are
  // complete, but requiring a CHOICE is different from requiring disclosure.
  static const _genderOptions = [
    'Male',
    'Female',
    'Other',
    'Prefer not to say',
  ];
  String? _selectedGender;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = ref.read(profileProvider);
    _nameCtrl.text   = p?.name   ?? '';
    _stateCtrl.text  = p?.state  ?? '';
    _dobCtrl.text    = p?.dob    ?? '';
    _mobileCtrl.text = p?.mobile ?? '';
    _cityCtrl.text   = p?.city   ?? '';
    _pinCtrl.text    = p?.pincode ?? '';
    _selectedGender  = p?.gender;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _stateCtrl.dispose();
    _dobCtrl.dispose();
    _mobileCtrl.dispose();
    _cityCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 20),
      firstDate: DateTime(1940),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _dobCtrl.text =
            '${picked.year.toString().padLeft(4, '0')}-'
            '${picked.month.toString().padLeft(2, '0')}-'
            '${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _stateCtrl.text.trim().isEmpty) {
      _snack('Name and State are required.');
      return;
    }
    // Gender is required so the admin statistics are complete. 'Prefer not
    // to say' is one of the options, so nobody is forced to disclose —
    // they just have to make a choice rather than leaving it blank.
    if ((_selectedGender ?? '').trim().isEmpty) {
      _snack('Please select a gender.');
      return;
    }
    final pin = _pinCtrl.text.trim();
    if (pin.isNotEmpty && pin.length != 6) {
      _snack('Pincode should be 6 digits.');
      return;
    }
    final mob = _mobileCtrl.text.trim();
    if (mob.isNotEmpty && mob.length < 10) {
      _snack('Mobile number looks too short.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(profileProvider.notifier).saveProfile(
            name:    _nameCtrl.text,
            state:   _stateCtrl.text,
            dob:     _dobCtrl.text.trim().isEmpty ? null : _dobCtrl.text.trim(),
            mobile:  mob.isEmpty ? null : mob,
            city:    _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
            pincode: pin.isEmpty ? null : pin,
            gender:  _selectedGender,
          );
      _snack('Profile saved.');
    } catch (e) {
      _snack('Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final theme   = Theme.of(context);

    if (profile == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view your dashboard.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Dashboard')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ── Avatar + name ──────────────────────────────────────────────
            UserAvatar(profile: profile, radius: 44),
            const SizedBox(height: 12),
            Text(
              profile.name.isNotEmpty ? profile.name : profile.displayName,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(profile.email,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor)),
            const SizedBox(height: 16),

            // ── Score card ─────────────────────────────────────────────────
            Card(
              elevation: 0,
              color: theme.colorScheme.secondaryContainer,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                child: Column(children: [
                  Text('Total Points', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text('${profile.totalScore}',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ]),
              ),
            ),

            // ── Incomplete profile reminder ────────────────────────────────
            if (!profile.profileComplete) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline_rounded, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          'Kindly complete your profile — it only takes a moment.')),
                ]),
              ),
            ],
            const SizedBox(height: 24),

            // ── Form fields ────────────────────────────────────────────────
            const AttemptPieChart(),
            const SizedBox(height: 12),
            _usernameTile(theme, profile),
            const SizedBox(height: 12),
            _field(_nameCtrl,  'Full name *',             Icons.badge_outlined),
            const SizedBox(height: 12),
            _field(_stateCtrl, 'State *',                 Icons.map_outlined),
            const SizedBox(height: 12),

            // Gender dropdown
            DropdownButtonFormField<String>(
              value: _selectedGender,
              decoration: const InputDecoration(
                labelText: 'Gender *',
                prefixIcon: Icon(Icons.wc_outlined),
                border: OutlineInputBorder(),
              ),
              items: _genderOptions
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: (val) => setState(() => _selectedGender = val),
            ),
            const SizedBox(height: 12),

            // Date of birth
            TextField(
              controller: _dobCtrl,
              readOnly: true,
              onTap: _pickDob,
              decoration: const InputDecoration(
                labelText: 'Date of birth (optional)',
                prefixIcon: Icon(Icons.cake_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            _field(_mobileCtrl, 'Mobile number (optional)',
                Icons.phone_outlined,
                keyboard: TextInputType.phone),
            const SizedBox(height: 12),
            _field(_cityCtrl,  'City (optional)',          Icons.location_city_outlined),
            const SizedBox(height: 12),
            _field(_pinCtrl,   'Pincode (optional)',       Icons.pin_drop_outlined,
                keyboard: TextInputType.number),
            const SizedBox(height: 24),

            // ── Save button ────────────────────────────────────────────────
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52)),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_rounded),
              label: Text(_saving ? 'Saving...' : 'Save profile'),
              onPressed: _saving ? null : _save,
            ),
            const SizedBox(height: 12),

            // ── Appearance ─────────────────────────────────────────────────
            Card(
              child: Builder(
                builder: (context) {
                  final mode = ref.watch(themeModeProvider);
                  final isDark = mode == ThemeMode.dark ||
                      (mode == ThemeMode.system &&
                          MediaQuery.platformBrightnessOf(context) ==
                              Brightness.dark);
                  return SwitchListTile(
                    value: isDark,
                    onChanged: (v) =>
                        ref.read(themeModeProvider.notifier).toggleDark(v),
                    title: const Text('Dark mode',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(mode == ThemeMode.system
                        ? 'Following your system setting'
                        : (isDark ? 'On' : 'Off')),
                    secondary: Icon(
                        isDark
                            ? Icons.dark_mode_rounded
                            : Icons.light_mode_rounded,
                        color: theme.colorScheme.primary),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            // ── Sign out ───────────────────────────────────────────────────
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                foregroundColor: theme.colorScheme.error,
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
              onPressed: () async {
                await ref.read(profileProvider.notifier).signOut();
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Public handle row. Separate from the main form because it saves
  /// independently (it needs a uniqueness transaction) and is rate-limited
  /// to one change per 30 days.
  Widget _usernameTile(ThemeData theme, UserProfile? profile) {
    final current = profile?.username;
    final wait = profile?.daysUntilUsernameChangeAllowed ?? 0;
    final locked = current != null && wait > 0;

    return Card(
      child: ListTile(
        leading: const Icon(Icons.alternate_email_rounded),
        title: Text(current == null ? 'Choose a username' : '@$current'),
        subtitle: Text(current == null
            ? 'Lets other players find you'
            : locked
                ? 'Can be changed in $wait day${wait == 1 ? '' : 's'}'
                : 'Tap to change'),
        trailing: locked
            ? const Icon(Icons.lock_outline_rounded, size: 18)
            : const Icon(Icons.edit_rounded, size: 18),
        onTap: locked ? null : () => _editUsername(current),
      ),
    );
  }

  Future<void> _editUsername(String? current) async {
    final ctrl = TextEditingController(text: current ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choose a username'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                prefixText: '@',
                hintText: 'e.g. quiz_master',
                helperText: '3-20 characters. Letters, numbers, underscore.',
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'You can change this once every 30 days, so pick carefully.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (value == null) return;

    setState(() => _saving = true);
    try {
      await ref.read(profileProvider.notifier).setUsername(value);
      _snack('Username saved.');
    } on StateError catch (e) {
      // Validation and "already taken" both surface as readable messages.
      _snack(e.message);
    } catch (e) {
      _snack('Could not save username: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController c, String label, IconData icon,
      {TextInputType? keyboard}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
    );
  }
}
