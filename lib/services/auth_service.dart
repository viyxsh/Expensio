/// A signed-in (or guest) identity, independent of the auth provider.
class AppUser {
  final String id;
  final String? displayName;
  final String? email;

  /// True while the user is a guest (anonymous) and hasn't linked an account.
  final bool isGuest;

  const AppUser({
    required this.id,
    this.displayName,
    this.email,
    this.isGuest = true,
  });
}

/// Provider-agnostic auth. [LocalAuthService] is the no-network fallback used
/// when Firebase isn't configured; [FirebaseAuthService] wraps Firebase Auth.
abstract class AuthService {
  AppUser? get currentUser;

  /// Emits on sign-in / sign-out / guest→account linking.
  Stream<AppUser?> authStateChanges();

  /// Sign in anonymously (guest). Returns the resulting user.
  Future<AppUser> signInAsGuest();

  Future<void> signOut();
}

/// Local-only identity used when Firebase isn't set up. A single stable guest
/// id keeps the existing on-device data working with no network.
class LocalAuthService implements AuthService {
  static const _localGuest = AppUser(id: 'local-guest', isGuest: true);

  @override
  AppUser? get currentUser => _localGuest;

  @override
  Stream<AppUser?> authStateChanges() => Stream.value(_localGuest);

  @override
  Future<AppUser> signInAsGuest() async => _localGuest;

  @override
  Future<void> signOut() async {}
}
