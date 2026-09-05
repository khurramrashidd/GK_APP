import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a Google search for [query].
///
/// Uses [LaunchMode.inAppBrowserView], which on Android is a Chrome Custom Tab:
/// it opens *inside* the app (tinted to the app's theme, back button returns
/// straight to the quiz) but is still a real browser, so Google serves normal
/// results. A plain embedded WebView is deliberately NOT used — Google blocks
/// search in embedded WebViews with "This browser or app may not be secure".
///
/// Falls back to the external browser if the in-app view isn't available.
Future<bool> openGoogleSearch(String query) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return false;

  final uri = Uri.https('www.google.com', '/search', {'q': trimmed});

  try {
    return await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  } catch (_) {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

/// Small "Read more on internet" button used under a quiz question.
class GoogleSearchButton extends StatelessWidget {
  /// The question text to search for.
  final String query;

  /// Renders as a compact text button instead of an outlined one.
  final bool compact;

  const GoogleSearchButton({
    super.key,
    required this.query,
    this.compact = false,
  });

  Future<void> _open(BuildContext context) async {
    final ok = await openGoogleSearch(query);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open a browser on this device.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const icon = Icon(Icons.travel_explore_rounded, size: 18);
    const label = Text('Read more on internet');

    if (compact) {
      return TextButton.icon(
        icon: icon,
        label: label,
        onPressed: () => _open(context),
      );
    }
    return OutlinedButton.icon(
      icon: icon,
      label: label,
      onPressed: () => _open(context),
    );
  }
}
