import '../data/repository.dart';
import '../state/app_state.dart';
import 'auth_service.dart';
import 'session_controller.dart';

/// Global handle to the active data + auth services, chosen once at startup:
/// Firebase-backed when configured, local Hive otherwise. Screens migrate to
/// read from [Services.repository] (Phase 1 to 2); until then they may still use
/// HiveService directly, which is why [firebaseActive] is exposed.
class Services {
  Services._();

  static late ExpensioRepository repository;
  static late AuthService auth;

  /// Reactive in-memory view of [repository] that screens listen to.
  static late AppState state;

  /// Keeps [repository] + [state] bound to the signed-in user (cloud mode).
  /// Null in local-only mode, where the uid never changes.
  static SessionController? session;

  /// True when a Firebase project is configured and a guest session is active.
  static bool firebaseActive = false;

  /// The signed-in user's id, their Firebase uid in cloud mode, or a stable
  /// local id otherwise. This id must be a member of any group/expense the user
  /// creates, both so the security rules permit the write and so the data syncs
  /// back to them. Used as the id of the user's own ("You") profile.
  static String get currentUserId => auth.currentUser?.id ?? 'local-guest';
}
