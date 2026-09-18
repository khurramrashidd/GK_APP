import 'package:flutter/services.dart';

/// Answer feedback sounds.
///
/// IMPORTANT — read before expecting audio:
///
/// This currently uses Flutter's BUILT-IN system sounds (SystemSoundType),
/// which need no package, no asset files and no licensing. The trade-off is
/// that the platform only exposes two generic sounds, so correct and wrong
/// are distinguished mainly by the HAPTIC pattern that accompanies them.
///
/// To get real distinct tones you need two things I cannot provide from
/// here: an audio package, and actual sound FILES (binary audio, which I
/// can't author). When you want that:
///
///   1) flutter pub add audioplayers
///   2) download two short CC0 (public-domain) effects — freesound.org with
///      the CC0 filter, or pixabay.com/sound-effects, both free for
///      commercial use with no attribution required
///   3) save them as assets/sounds/correct.mp3 and assets/sounds/wrong.mp3
///   4) add to pubspec.yaml under flutter: assets: - assets/sounds/
///   5) swap the bodies below for AudioPlayer().play(AssetSource(...))
///
/// Keeping this behind one service means that swap touches this file only.
class SoundService {
  static bool _enabled = true;

  /// Lets the user mute feedback without any of the call sites caring.
  static void setEnabled(bool value) => _enabled = value;
  static bool get isEnabled => _enabled;

  static Future<void> correct() async {
    if (!_enabled) return;
    try {
      await SystemSound.play(SystemSoundType.click);
      await HapticFeedback.lightImpact();
    } catch (_) {
      // Audio is a nicety — never let it break answering a question.
    }
  }

  static Future<void> wrong() async {
    if (!_enabled) return;
    try {
      await SystemSound.play(SystemSoundType.alert);
      // Heavier double-tap so wrong FEELS different even where the two
      // system sounds are similar.
      await HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 90));
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }
}
