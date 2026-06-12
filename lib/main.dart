import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'data/hive_repository.dart';
import 'services/auth_service.dart';
import 'services/firebase_bootstrap.dart';
import 'services/hive_service.dart';
import 'services/notification_service.dart';
import 'services/services.dart';
import 'services/session_controller.dart';
import 'state/app_state.dart';
import 'screens/main_shell.dart';
import 'utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await dotenv.load(fileName: '.env');
  await HiveService.init();
  await NotificationService.init();

  // Try Firebase (multi-device). Falls back to local-only mode when the
  // project isn't configured yet — see SETUP.md.
  final stack = await FirebaseBootstrap.start();
  if (stack != null) {
    Services.firebaseActive = true;
    Services.auth = stack.auth;
    Services.repository = stack.repository;

    // The session controller owns the repository↔uid binding: it performs the
    // initial subscribe and rebuilds the cache whenever the signed-in user
    // changes (sign-in / sign-out / switching accounts).
    Services.state = AppState(stack.repository);
    Services.session = SessionController(stack.auth, Services.state);
    await Services.session!.start();
    debugPrint('[Expensio] ☁️  CLOUD mode — Firebase uid='
        '${stack.auth.currentUser?.id}');
  } else {
    Services.firebaseActive = false;
    Services.auth = LocalAuthService();
    Services.repository = HiveRepository();
    Services.state = AppState(Services.repository);
    await Services.state.init();
    // Local mode has a single stable guest; ensure its "You" profile once.
    await Services.state.ensureSelfProfile(Services.currentUserId);
    debugPrint('[Expensio] 📦 LOCAL mode — Hive (Firebase not active)');
  }

  runApp(const ExpensioApp());
}

class ExpensioApp extends StatelessWidget {
  const ExpensioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expensio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const MainShell(),
    );
  }
}