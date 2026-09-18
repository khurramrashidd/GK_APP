import 'package:flutter/material.dart';
import '../../data/models/user_profile.dart';

/// Shows the user's real photo when one exists (currently only Google
/// Sign-In provides this), otherwise a colored circle with the first letter
/// of their name. Swap this widget's body for a real upload/crop flow later —
/// every call site already goes through here, so nothing else needs to change.
class UserAvatar extends StatelessWidget {
  final UserProfile? profile;
  final double radius;

  const UserAvatar({super.key, required this.profile, this.radius = 20});

  // Small fixed palette so colors stay pleasant and on-theme regardless of name.
  static const _palette = [
    Color(0xFF5C6BC0), Color(0xFFEF5350), Color(0xFF26A69A),
    Color(0xFFAB47BC), Color(0xFFFFA726), Color(0xFF42A5F5),
    Color(0xFF66BB6A), Color(0xFFEC407A), Color(0xFF7E57C2),
    Color(0xFF26C6DA),
  ];

  String get _letter {
    final source = (profile?.name.trim().isNotEmpty ?? false)
        ? profile!.name.trim()
        : (profile?.displayName.trim() ?? '');
    return source.isNotEmpty ? source[0].toUpperCase() : '';
  }

  Color get _bgColor {
    final source = (profile?.name.trim().isNotEmpty ?? false)
        ? profile!.name.trim()
        : (profile?.displayName.trim() ?? profile?.email ?? '');
    if (source.isEmpty) return _palette.first;
    final hash = source.codeUnits.fold<int>(0, (a, b) => a + b);
    return _palette[hash % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final photo = profile?.photoUrl;

    if (photo != null && photo.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        backgroundImage: NetworkImage(photo),
        // If the network image fails to load, Flutter keeps the background
        // color showing beneath it — no crash, just a plain circle. Falling
        // fully back to the letter avatar isn't directly supported by
        // CircleAvatar, so callers get a graceful color circle in that case.
        onBackgroundImageError: (_, __) {},
      );
    }

    final letter = _letter;
    if (letter.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(Icons.person_rounded,
            size: radius, color: Theme.of(context).colorScheme.primary),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: _bgColor,
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.9,
        ),
      ),
    );
  }
}
