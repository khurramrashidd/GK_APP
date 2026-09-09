import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import 'terms_screen.dart';

/// Wraps the signed-in app and forces Terms acceptance before anything else
/// is reachable.
///
/// Covers all three cases the product needs:
///  * brand-new user — accepts during first run;
///  * existing user who has never accepted — gets the gate on next launch;
///  * any user after the Terms are updated (AppConstants.termsVersion is
///    bumped) — gets the gate again, because acceptance is stored as a
///    version number, not a boolean.
///
/// Declining signs the user out (handled inside TermsScreen), so there's no
/// way to reach app content without accepting.
class TermsGate extends ConsumerWidget {
  final Widget child;
  const TermsGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    if (profile == null) return child; // not signed in yet — login handles it

    final needs = ref.read(profileProvider.notifier).needsTermsAcceptance;
    if (!needs) return child;

    return const TermsScreen();
  }
}
