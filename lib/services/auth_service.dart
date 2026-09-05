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
