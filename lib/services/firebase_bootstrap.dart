import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/repository.dart';
import '../data/firestore_repository.dart';
import '../firebase_options.dart';
import 'auth_service.dart';
import 'firebase_auth_service.dart';

/// The Firebase-backed stack: an auth service and a cloud repository tied to
/// the signed-in user.
class FirebaseStack {
  final AuthService auth;
  final ExpensioRepository repository;
  const FirebaseStack(this.auth, this.repository);
}

/// Guarded Firebase startup. Returns a [FirebaseStack] when Firebase is
/// configured and a guest session is established; returns null otherwise so
/// the app falls back to local-only mode (Hive + LocalAuthService).
class FirebaseBootstrap {
  static Future<FirebaseStack?> start() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      // Offline persistence is the local cache for the repository layer.
      FirebaseFirestore.instance.settings =
          const Settings(persistenceEnabled: true);

      final auth = FirebaseAuthService();
      final user = await auth.signInAsGuest();
      return FirebaseStack(auth, FirestoreRepository(uid: user.id));
    } catch (e, st) {
      debugPrint('[Firebase] Not configured / init failed — local mode. $e\n$st');
      return null;
    }
  }
}
