import 'dart:async';
import '../data/firestore_repository.dart';
import '../state/app_state.dart';
import 'auth_service.dart';
import 'services.dart';

/// Keeps the cloud data layer in sync with the signed-in user (cloud mode
/// only). The Firestore repository is scoped to a uid, so when the user signs
/// into a different account — a different uid — the repository and the shared
/// [AppState] must be rebuilt to point at that account's data. Linking an
/// account (guest→email/Google) keeps the same uid, so it only refreshes the
/// profile name; no rebind.
class SessionController {
  SessionController(this._auth, this._state);

  final AuthService _auth;
  final AppState _state;

  String? _boundUid;
  StreamSubscription<AppUser?>? _sub;

  /// Establish the initial binding (before the first frame), then keep it in
  /// sync as auth changes.
  Future<void> start() async {
    final user = _auth.currentUser ?? await _auth.signInAsGuest();
    await _bindTo(user);
    _sub = _auth.authStateChanges().listen(_onAuthChanged);
  }

  Future<void> _onAuthChanged(AppUser? user) async {
    if (user == null) {
      // Fully signed out — drop back to a fresh guest. The resulting sign-in
      // re-emits and binds below.
      _boundUid = null;
      await _auth.signInAsGuest();
      return;
    }
    if (user.id != _boundUid) {
      await _bindTo(user);
    } else {
      // Same account, changed profile (e.g. just linked email/Google).
      await _state.ensureSelfProfile(user.id, name: _selfName(user));
    }
  }

  Future<void> _bindTo(AppUser user) async {
    _boundUid = user.id;
    final repo = FirestoreRepository(uid: user.id);
    Services.repository = repo;
    await _state.bindTo(repo);
    await _state.ensureSelfProfile(user.id, name: _selfName(user));
  }

  /// Best display name for the user's own profile, or null to keep the current.
  String? _selfName(AppUser user) {
    if (user.displayName != null && user.displayName!.trim().isNotEmpty) {
      return user.displayName!.trim();
    }
    if (user.email != null && user.email!.contains('@')) {
      return user.email!.split('@').first;
    }
    return null; // keep "You"
  }

  void dispose() {
    _sub?.cancel();
  }
}
