import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/content_update_model.dart';
import '../../providers/database_provider.dart';

/// Admin > Publish app update.
///
/// For side-loaded APK distribution before the app is on the Play Store.
/// You upload the APK to GitHub Releases, paste the download link here, and
/// every existing user sees an update banner plus a "What's new" entry.
///
/// Once the app IS on Play, leave this unset — Play handles updates itself,
/// and the banner disappears because the published build number will no
/// longer be ahead of what users are running.
class AdminPublishUpdateScreen extends ConsumerStatefulWidget {
  const AdminPublishUpdateScreen({super.key});

  @override
  ConsumerState<AdminPublishUpdateScreen> createState() =>
      _AdminPublishUpdateScreenState();
}

class _AdminPublishUpdateScreenState
    extends ConsumerState<AdminPublishUpdateScreen> {
  final _buildCtrl = TextEditingController();
  final _versionCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _mandatory = false;
  bool _adminsOnly = false;
  bool _busy = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _buildCtrl.dispose();
    _versionCtrl.dispose();
    _urlCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _publish() async {
    final build = int.tryParse(_buildCtrl.text.trim());
    final url = _urlCtrl.text.trim();

    if (build == null) {
      _snack('Build number must be a whole number.');
      return;
    }
    if (build <= AppConstants.appBuildNumber) {
      // Publishing a build <= the one you're running means nobody sees it —
      // almost always a forgotten bump in app_constants.dart.
      _snack('Build $build is not newer than this app, which is build '
          '${AppConstants.appBuildNumber}. Bump appBuildNumber in '
          'app_constants.dart first, then rebuild.');
      return;
    }
    if (!url.startsWith('http')) {
      _snack('Enter the full download URL (starting with https://).');
      return;
    }

    setState(() => _busy = true);
    try {
      final fs = ref.read(firestoreServiceProvider);
      await fs.setAppSetting('latestBuildNumber', build);
      await fs.setAppSetting('latestVersionName', _versionCtrl.text.trim());
      await fs.setAppSetting('apkUrl', url);
      await fs.setAppSetting('releaseNotes', _notesCtrl.text.trim());
      await fs.setAppSetting('updateMandatory', _mandatory);
      await fs.setAppSetting('updateAdminsOnly', _adminsOnly);

      // Also drop it into the What's New feed so it shows up there too.
      // Build the title in a plain variable — nesting quotes inside a ${}
      // interpolation is legal Dart but hard to read and easy to break.
      final vName = _versionCtrl.text.trim();
      final title =
          vName.isEmpty ? 'App update available' : 'App update available — v$vName';

      // Admin-only builds are not announced publicly — the feed is visible
      // to everyone, so posting there would defeat the point.
      if (!_adminsOnly) {
        await fs.postContentUpdate(ContentUpdateModel(
        id: '',
        kind: 'questions',
        title: title,
        detail: _notesCtrl.text.trim().isEmpty
            ? 'Tap the update banner on the home screen to download.'
            : _notesCtrl.text.trim(),
        ));
      }

      _snack('Update published. Users will see it shortly.');
    } catch (e) {
      _snack('Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    try {
      await ref.read(firestoreServiceProvider).setAppSetting('apkUrl', '');
      _snack('Update banner cleared.');
    } catch (e) {
      _snack('Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider).valueOrNull ?? const {};

    // Prefill once from what's currently published, so editing is easy.
    if (!_prefilled && settings.isNotEmpty) {
      _prefilled = true;
      _buildCtrl.text = (settings['latestBuildNumber'] ?? '').toString();
      _versionCtrl.text = (settings['latestVersionName'] ?? '').toString();
      _urlCtrl.text = (settings['apkUrl'] ?? '').toString();
      _notesCtrl.text = (settings['releaseNotes'] ?? '').toString();
      _mandatory = (settings['updateMandatory'] ?? false) as bool;
      _adminsOnly = (settings['updateAdminsOnly'] ?? false) as bool;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Publish app update')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('This app is build ${AppConstants.appBuildNumber} '
                      '(v${AppConstants.appVersion})',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text(
                      'Publish a HIGHER build number than this, with a link '
                      'to the APK, and every user on an older build sees an '
                      'update banner.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _buildCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'New build number *',
              helperText: 'Must match appBuildNumber in the build you upload',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _versionCtrl,
            decoration: const InputDecoration(
              labelText: 'Version name (e.g. 1.1.0)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: 'APK download URL *',
              hintText:
                  'https://github.com/<you>/<repo>/releases/download/v1.1.0/app-release.apk',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: "What's new in this version",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _adminsOnly,
            onChanged: _busy ? null : (v) => setState(() => _adminsOnly = v),
            title: const Text('Admins only'),
            subtitle: const Text(
                'Regular users are not told about this build. Use it when '
                'the release only changes the admin panel — no point pushing '
                'everyone through a large download.'),
          ),
          SwitchListTile(
            value: _mandatory,
            onChanged: _busy ? null : (v) => setState(() => _mandatory = v),
            title: const Text('Mandatory update'),
            subtitle: const Text(
                'Banner cannot be dismissed. Use sparingly — only when an '
                'older build is genuinely broken.'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52)),
            icon: const Icon(Icons.publish_rounded),
            label: const Text('Publish update'),
            onPressed: _busy ? null : _publish,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.visibility_off_rounded),
            label: const Text('Clear update banner'),
            onPressed: _busy ? null : _clear,
          ),
        ],
      ),
    );
  }
}
