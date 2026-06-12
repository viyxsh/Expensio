// NOTE: imports resolve only after `flutter pub get` with the Firebase deps.
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';

/// [AuthService] backed by Firebase Auth. Phase 1 uses anonymous (guest)
/// sign-in; Phase 2 adds email/Google/Apple linking to upgrade the same uid.
class FirebaseAuthService implements AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

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

  @override
  Stream<AppUser?> authStateChanges() => _auth.authStateChanges().map(_map);

  @override
  Future<AppUser> signInAsGuest() async {
    final existing = _auth.currentUser;
    if (existing != null) return _map(existing)!;
    final cred = await _auth.signInAnonymously();
    return _map(cred.user)!;
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
