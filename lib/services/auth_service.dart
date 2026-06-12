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

/// A user-facing auth failure with a friendly [message]. The [code] is the
/// provider's raw error code (for logging / branching).
class AuthException implements Exception {
  final String code;
  final String message;
  const AuthException(this.code, this.message);

  @override
  String toString() => 'AuthException($code): $message';
}

/// Provider-agnostic auth. [LocalAuthService] is the no-network fallback used
/// when Firebase isn't configured; [FirebaseAuthService] wraps Firebase Auth.
///
/// The app is guest-first: it always starts with [signInAsGuest]. A guest can
/// then *link* an email/Google credential to upgrade the SAME account in place
/// (no data migration), or sign into an existing account on a new device.
abstract class AuthService {
  AppUser? get currentUser;

  /// Emits on sign-in / sign-out / guest→account linking / profile changes.
  Stream<AppUser?> authStateChanges();

  /// Sign in anonymously (guest). Returns the resulting user.
  Future<AppUser> signInAsGuest();

  /// Create an account from the current guest by linking an email credential —
  /// keeps the same uid so existing data stays. Throws [AuthException].
  Future<AppUser> registerWithEmail(String email, String password);

  /// Sign into an existing email account (e.g. on a new device). Throws
  /// [AuthException].
  Future<AppUser> signInWithEmail(String email, String password);

  /// Link Google to the current guest (or sign into the Google account if it
  /// already exists). Throws [AuthException]; a cancelled flow throws code
  /// `cancelled`.
  Future<AppUser> signInWithGoogle();

  Future<void> signOut();
}

/// Local-only identity used when Firebase isn't set up. A single stable guest
/// id keeps the existing on-device data working with no network. Account
/// features are unavailable and surface a clear [AuthException].
class LocalAuthService implements AuthService {
  static const _localGuest = AppUser(id: 'local-guest', isGuest: true);
  static const _unavailable = AuthException(
    'cloud-unavailable',
    'Accounts need cloud mode, which isn\'t configured on this build.',
  );

  @override
  AppUser? get currentUser => _localGuest;

  @override
  Stream<AppUser?> authStateChanges() => Stream.value(_localGuest);

  @override
  Future<AppUser> signInAsGuest() async => _localGuest;

  @override
  Future<AppUser> registerWithEmail(String email, String password) async =>
      throw _unavailable;

  @override
  Future<AppUser> signInWithEmail(String email, String password) async =>
      throw _unavailable;

  @override
  Future<AppUser> signInWithGoogle() async => throw _unavailable;

  @override
  Future<void> signOut() async {}
}
