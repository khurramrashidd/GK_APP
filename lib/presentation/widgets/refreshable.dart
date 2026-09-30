import 'package:flutter/material.dart';

/// Wraps a scrollable in pull-to-refresh, and gives you a matching app-bar
/// action, so both gestures do the same thing everywhere in the app.
///
/// Pull-to-refresh alone isn't discoverable (nothing on screen says it
/// exists) and an icon alone ignores the gesture people already expect from
/// every other app — so this pairs them rather than picking one.
class PullToRefresh extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;

  const PullToRefresh({super.key, required this.onRefresh, required this.child});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      // Ensures the gesture works even when content is shorter than the
      // screen — otherwise a half-empty list can't be pulled at all.
      child: _AlwaysScrollable(child: child),
    );
  }
}

class _AlwaysScrollable extends StatelessWidget {
  final Widget child;
  const _AlwaysScrollable({required this.child});

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: const _BouncyBehavior(),
      child: child,
    );
  }
}

class _BouncyBehavior extends ScrollBehavior {
  const _BouncyBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics());
}

/// App-bar refresh button. Shows a spinner while the refresh is running so
/// tapping it gives immediate feedback rather than appearing to do nothing.
class RefreshAction extends StatefulWidget {
  final Future<void> Function() onRefresh;
  const RefreshAction({super.key, required this.onRefresh});

  @override
  State<RefreshAction> createState() => _RefreshActionState();
}

class _RefreshActionState extends State<RefreshAction> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    return IconButton(
      tooltip: 'Refresh',
      icon: const Icon(Icons.refresh_rounded),
      onPressed: _run,
    );
  }
}
