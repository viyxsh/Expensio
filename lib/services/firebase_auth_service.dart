// NOTE: imports resolve only after `flutter pub get` with the Firebase deps.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'auth_service.dart';

/// [AuthService] backed by Firebase Auth. The app starts anonymous (guest);
/// email/Google credentials are *linked* to that same uid so a guest upgrades
/// in place without losing data. If the credential already belongs to another
/// account we fall back to signing into it (data merge is Phase 2b).
class FirebaseAuthService implements AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  AppUser? _map(User? u) => u == null
      ? null
      : AppUser(
          id: u.uid,
          displayName: u.displayName,
          email: u.email,
          isGuest: u.isAnonymous,
        );

  @override
  AppUser? get currentUser => _map(_auth.currentUser);

  // userChanges() (not authStateChanges) so the UI also reacts to linking and
  // profile updates that keep the same uid, not just sign-in/out.
  @override
  Stream<AppUser?> authStateChanges() => _auth.userChanges().map(_map);

  @override
  Future<AppUser> signInAsGuest() async {
    final existing = _auth.currentUser;
    if (existing != null) return _map(existing)!;
    try {
      final cred = await _auth.signInAnonymously();
      return _map(cred.user)!;
    } on FirebaseAuthException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<AppUser> registerWithEmail(String email, String password) =>
      _linkOrSignIn(
        EmailAuthProvider.credential(email: email.trim(), password: password),
      );

  @override
  Future<AppUser> signInWithEmail(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return _map(cred.user)!;
    } on FirebaseAuthException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<AppUser> signInWithGoogle() async {
    final GoogleSignInAccount? googleUser;
    try {
      googleUser = await _googleSignIn.signIn();
    } catch (e) {
      throw AuthException('google-failed', 'Google sign-in failed: $e');
    }
    if (googleUser == null) {
      throw const AuthException('cancelled', 'Sign-in cancelled.');
    }
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return _linkOrSignIn(credential);
  }

  @override
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  /// Link [cred] to the current guest; if it already belongs to another
  /// account, sign into that account instead.
  Future<AppUser> _linkOrSignIn(AuthCredential cred) async {
    final current = _auth.currentUser;
    try {
      if (current != null && current.isAnonymous) {
        final res = await current.linkWithCredential(cred);
        return _map(res.user)!;
      }
      final res = await _auth.signInWithCredential(cred);
      return _map(res.user)!;
    } on FirebaseAuthException catch (e) {
      // The credential is already attached to a real account — sign into it.
      // (Any guest data on THIS device won't be merged yet — see Phase 2b.)
      if (e.code == 'credential-already-in-use' ||
          e.code == 'email-already-in-use') {
        final res = await _auth.signInWithCredential(
          e.credential ?? cred,
        );
        return _map(res.user)!;
      }
      throw _translate(e);
    }
  }

  AuthException _translate(FirebaseAuthException e) {
    final msg = switch (e.code) {
      'invalid-email' => 'That email address looks invalid.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' =>
        'Incorrect email or password.',
      'email-already-in-use' =>
        'An account already exists for that email — sign in instead.',
      'weak-password' => 'Password is too weak (use at least 6 characters).',
      'network-request-failed' =>
        'No connection. Check your network and try again.',
      'too-many-requests' => 'Too many attempts. Try again later.',
      'operation-not-allowed' =>
        'This sign-in method isn\'t enabled for the project.',
      _ => e.message ?? 'Authentication failed. Please try again.',
    };
    return AuthException(e.code, msg);
  }
}
