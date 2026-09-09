import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

/// Thin wrapper over Firebase Auth supporting Google + email/password.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  User? get currentUser => _auth.currentUser;
  Stream<User?> get userStateStream => _auth.authStateChanges();

  // --------------------------- Google -------------------------------------
  Future<UserCredential?> signInWithGoogle() async {
    // Web: Firebase's own popup flow. Simpler and more current than routing
    // through the google_sign_in plugin's web implementation, and needs no
    // extra OAuth client setup beyond the Google provider already being
    // enabled in Firebase Auth (it already is, for the mobile flow below).
    if (kIsWeb) {
      return await _auth.signInWithPopup(GoogleAuthProvider());
    }

    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null; // user cancelled

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    return await _auth.signInWithCredential(credential);
  }

  // ----------------------- Email / password --------------------------------
  // ------------------------------ Guest ------------------------------------

  /// Signs in anonymously so someone can try the app without creating an
  /// account. Firebase issues a real (anonymous) uid, so profiles, history
  /// and scores all work exactly as they do for a registered user.
  ///
  /// REQUIRES: Anonymous sign-in must be enabled in Firebase Console >
  /// Authentication > Sign-in method. If it isn't, this throws and the login
  /// screen reports it rather than failing silently.
  ///
  /// Caveat worth knowing: an anonymous account lives on that single device
  /// and is lost if the app is uninstalled or storage cleared — which is why
  /// the app nudges guests to upgrade to a real account.
  Future<UserCredential> signInAsGuest() async {
    return await _auth.signInAnonymously();
  }

  /// Converts the CURRENT anonymous account into a permanent email/password
  /// account, keeping the same uid — so all their history, streak and
  /// bookmarks carry over instead of starting from scratch.
  Future<UserCredential> upgradeGuestWithEmail(
      String email, String password) async {
    final user = _auth.currentUser;
    if (user == null || !user.isAnonymous) {
      throw StateError('Not signed in as a guest.');
    }
    final cred =
        EmailAuthProvider.credential(email: email, password: password);
    return await user.linkWithCredential(cred);
  }

  /// True when the signed-in user is a guest (anonymous) account.
  bool get isGuest => _auth.currentUser?.isAnonymous ?? false;

  Future<UserCredential> registerWithEmail(
      String email, String password, String displayName) async {
    final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(), password: password);
    if (displayName.trim().isNotEmpty) {
      await cred.user?.updateDisplayName(displayName.trim());
    }
    return cred;
  }

  Future<UserCredential> loginWithEmail(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
        email: email.trim(), password: password);
  }

  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  // ----------------------------- Sign out ----------------------------------
  Future<void> signOut() async {
    if (!kIsWeb) {
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
    }
    await _auth.signOut();
  }
}
