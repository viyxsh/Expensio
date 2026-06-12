import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'data/hive_repository.dart';
import 'models/user_model.dart';
import 'services/auth_service.dart';
import 'services/firebase_bootstrap.dart';
import 'services/hive_service.dart';
import 'services/notification_service.dart';
import 'services/services.dart';
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
    debugPrint('[Expensio] ☁️  CLOUD mode — Firebase guest uid='
        '${stack.auth.currentUser?.id}');
  } else {
    Services.firebaseActive = false;
    Services.auth = LocalAuthService();
    Services.repository = HiveRepository();
    debugPrint('[Expensio] 📦 LOCAL mode — Hive (Firebase not active)');
  }

  // Reactive cache the screens listen to (works for Hive or Firestore).
  Services.state = AppState(Services.repository);
  await Services.state.init();

  // Ensure the signed-in user has a profile whose id == their auth uid. This
  // makes them a real, selectable member of the groups/expenses they create,
  // which the security rules require and which lets data sync back to them.
  if (Services.state.getUserById(Services.currentUserId) == null) {
    await Services.state.saveUser(
      UserModel(id: Services.currentUserId, name: 'You'),
    );
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