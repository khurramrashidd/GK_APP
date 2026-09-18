import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/legal/terms_and_conditions.dart';
import '../providers/auth_provider.dart';

/// Shows the Terms. In [readOnly] mode it's just a document (from About).
/// Otherwise it's the acceptance gate: the user must tick BOTH boxes to
/// continue, and cannot use the app until they do.
class TermsScreen extends ConsumerStatefulWidget {
  final bool readOnly;
  const TermsScreen({super.key, this.readOnly = false});

  @override
  ConsumerState<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends ConsumerState<TermsScreen> {
  bool _agreeTerms = false;
  bool _agreeErrors = false;
  bool _busy = false;

  bool get _canProceed => _agreeTerms && _agreeErrors;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await ref.read(profileProvider.notifier).acceptCurrentTerms();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
        setState(() => _busy = false);
        return;
      }
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _decline() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline terms?'),
        content: const Text(
            'You need to accept the Terms & Conditions to use the app. '
            'If you decline, you will be signed out.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Go back')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Decline & sign out'),
          ),
        ],
      ),
    );
    if (leave == true) {
      await ref.read(profileProvider.notifier).signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      // In gate mode the user must not be able to swipe/back out of it.
      canPop: widget.readOnly,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Terms & Conditions'),
          automaticallyImplyLeading: widget.readOnly,
        ),
        body: Column(
          children: [
            Expanded(
              child: Scrollbar(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: SelectableText(
                    TermsAndConditions.text,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                  ),
                ),
              ),
            ),
            if (!widget.readOnly)
              Material(
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _agreeTerms,
                        onChanged: (v) =>
                            setState(() => _agreeTerms = v ?? false),
                        title: const Text(
                            'I have read and accept the Terms & Conditions.'),
                      ),
                      CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _agreeErrors,
                        onChanged: (v) =>
                            setState(() => _agreeErrors = v ?? false),
                        title: const Text(
                            'I understand questions are largely AI-generated '
                            'and there can be wrong answers. I will report any '
                            'errors I find.'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                  foregroundColor: theme.colorScheme.error),
                              onPressed: _busy ? null : _decline,
                              child: const Text('Decline'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 48)),
                              onPressed:
                                  (_canProceed && !_busy) ? _accept : null,
                              child: _busy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Text('Accept & Continue'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Terms version ${AppConstants.termsVersion}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
