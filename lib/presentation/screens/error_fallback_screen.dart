import 'package:flutter/material.dart';

/// Shown instead of Flutter's red error screen whenever a widget fails to
/// build (wired up via ErrorWidget.builder in main.dart). The underlying
/// error is already sent to the admin dashboard by ErrorReporter — this
/// screen's only job is to not scare the user with a stack trace.
class ErrorFallbackScreen extends StatelessWidget {
  final String? details;
  const ErrorFallbackScreen({super.key, this.details});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded,
                    size: 72, color: theme.colorScheme.error),
                const SizedBox(height: 20),
                Text('Something went wrong',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text(
                  'This has already been reported to us automatically. '
                  'Please try again, and if it keeps happening, let us know.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.hintColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
