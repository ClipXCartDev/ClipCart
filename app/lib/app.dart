import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/onboarding_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/billing/plans_screen.dart';
import 'features/creator/creator_dashboard.dart';
import 'features/creator/upload_clip_screen.dart';
import 'features/editor/editor_screen.dart';
import 'features/home/home_shell.dart';
import 'features/player/clip_player_screen.dart';
import 'models/clip.dart';
import 'state/auth_controller.dart';

class ClipCartApp extends StatefulWidget {
  const ClipCartApp({super.key});
  @override
  State<ClipCartApp> createState() => _ClipCartAppState();
}

class _ClipCartAppState extends State<ClipCartApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthController>();
    _router = GoRouter(
      initialLocation: '/splash',
      refreshListenable: auth,
      redirect: (context, state) {
        final s = auth.status;
        final loc = state.matchedLocation;
        if (s == AuthStatus.unknown) return loc == '/splash' ? null : '/splash';
        final inAuthFlow = loc == '/login' || loc == '/register' || loc == '/onboarding';
        if (s == AuthStatus.guest) return inAuthFlow ? null : '/onboarding';
        // authed
        if (inAuthFlow || loc == '/splash') return '/home';
        return null;
      },
      routes: [
        GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
        GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
        GoRoute(path: '/home', builder: (_, __) => const HomeShell()),
        GoRoute(path: '/clip/:slug', builder: (c, s) => ClipPlayerScreen(slug: s.pathParameters['slug']!)),
        GoRoute(
          path: '/editor',
          builder: (c, s) => EditorScreen(title: s.extra is Clip ? (s.extra as Clip).title : null),
        ),
        GoRoute(path: '/plans', builder: (_, __) => const PlansScreen()),
        GoRoute(path: '/creator', builder: (_, __) => const CreatorDashboard()),
        GoRoute(path: '/creator/upload', builder: (_, __) => const UploadClipScreen()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ClipCart',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}
