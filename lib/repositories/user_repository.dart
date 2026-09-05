import 'package:firebase_auth/firebase_auth.dart';
import '../data/remote/firestore_service.dart';
import '../data/models/user_profile.dart';

class UserRepository {
  final FirestoreService _remote;
  UserRepository(this._remote);

  /// Called right after any successful sign-in: guarantees a users/{uid} doc,
  /// and keeps photoUrl in sync with the auth provider (e.g. Google) in case
  /// the person changed their photo since last sign-in.
  Future<UserProfile> ensureProfile(User user) async {
    final existing = await _remote.fetchUserProfile(user.uid);
    final authPhoto = user.photoURL;

    if (existing != null) {
      if (authPhoto != null && authPhoto != existing.photoUrl) {
        final updated = existing.copyWith(photoUrl: authPhoto);
        await _remote.saveUserProfile(updated);
        return updated;
      }
      return existing;
    }

    final fresh = UserProfile(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName ?? (user.email?.split('@').first ?? 'User'),
      photoUrl: authPhoto,
      profileComplete: false,
    );
    await _remote.createUserProfileIfMissing(fresh);
    return fresh;
  }

  Future<UserProfile?> load(String uid) => _remote.fetchUserProfile(uid);

  Future<void> save(UserProfile profile) => _remote.saveUserProfile(profile);

  Future<void> addScore(String uid, int points) =>
      _remote.incrementUserScore(uid, points);
}
