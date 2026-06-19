import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'data/hive_repository.dart';
import 'services/auth_service.dart';
import 'services/firebase_bootstrap.dart';
import 'services/hive_service.dart';
import 'services/notification_service.dart';
import 'services/services.dart';
import 'services/session_controller.dart';
import 'state/app_state.dart';
import 'screens/join_flow.dart';
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
  // project isn't configured yet. See SETUP.md.
  final stack = await FirebaseBootstrap.start();
  if (stack != null) {
    Services.firebaseActive = true;
    Services.auth = stack.auth;
    Services.repository = stack.repository;

    // The session controller owns the repository/uid binding: it performs the
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
    await Services.state.backfillPlaceholderFlags(Services.currentUserId);
    debugPrint('[Expensio] 📦 LOCAL mode — Hive (Firebase not active)');
  }

  runApp(const ExpensioApp());
}

class ExpensioApp extends StatefulWidget {
  const ExpensioApp({super.key});

  @override
  State<ExpensioApp> createState() => _ExpensioAppState();
}

class _ExpensioAppState extends State<ExpensioApp> {
  final _navKey = GlobalKey<NavigatorState>();
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    // Cold start via an invite link, then links received while running.
    final initial = await _appLinks.getInitialLink();
    if (initial != null) _handleUri(initial);
    _linkSub = _appLinks.uriLinkStream.listen(_handleUri);
  }

  void _handleUri(Uri uri) {
    final code = parseInviteCode(uri.toString());
    if (code == null) return;
    // Defer until the navigator + messenger are mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _navKey.currentContext;
      if (ctx != null) runJoinFlow(ctx, code);
    });
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expensio',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navKey,
      theme: AppTheme.theme,
      home: const MainShell(),
    );
  }
}