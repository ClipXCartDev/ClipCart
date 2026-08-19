import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'features/auth/devices_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/onboarding_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/billing/plans_screen.dart';
import 'features/creator/creator_dashboard.dart';
import 'features/creator/upload_clip_screen.dart';
import 'features/editor/editor_screen.dart';
import 'features/exports/exports_screen.dart';
import 'features/home/home_shell.dart';
import 'features/player/clip_player_screen.dart';
import 'features/settings/change_password_screen.dart';
import 'features/support/support_screen.dart';
import 'models/clip.dart';
import 'services/project_store.dart';
import 'state/auth_controller.dart';

/// Premium push-over transition: subtle fade + scale (0.96→1.0) + short slide-up,
/// ~250ms easeOutCubic. Used for routes that push over existing content.
Page<T> _fadeScalePage<T>(GoRouterState state, Widget child) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

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
        GoRoute(path: '/clip/:slug', pageBuilder: (c, s) => _fadeScalePage(s, ClipPlayerScreen(slug: s.pathParameters['slug']!))),
        GoRoute(
          path: '/player',
          pageBuilder: (c, s) {
            final m = s.extra as Map<String, dynamic>?;
            final clips = (m?['clips'] as List?)?.cast<Clip>() ?? const <Clip>[];
            return _fadeScalePage(s, ReelsPlayerScreen(clips: clips, startIndex: (m?['index'] as int?) ?? 0));
          },
        ),
        GoRoute(
          path: '/editor',
          pageBuilder: (c, s) {
            // extra may be a Clip (new edit) or a SavedProject (resume).
            final extra = s.extra;
            if (extra is SavedProject) {
              return _fadeScalePage(s, EditorScreen(resume: extra, title: extra.name));
            }
            final clip = extra is Clip ? extra : null;
            return _fadeScalePage(s, EditorScreen(clip: clip, title: clip?.title));
          },
        ),
        GoRoute(path: '/plans', pageBuilder: (c, s) => _fadeScalePage(s, const PlansScreen())),
        GoRoute(path: '/devices', pageBuilder: (c, s) => _fadeScalePage(s, const DevicesScreen())),
        GoRoute(path: '/exports', pageBuilder: (c, s) => _fadeScalePage(s, const ExportsScreen())),
        GoRoute(path: '/support', pageBuilder: (c, s) => _fadeScalePage(s, const SupportScreen())),
        GoRoute(path: '/change-password', pageBuilder: (c, s) => _fadeScalePage(s, const ChangePasswordScreen())),
        GoRoute(path: '/creator', pageBuilder: (c, s) => _fadeScalePage(s, const CreatorDashboard())),
        GoRoute(path: '/creator/upload', pageBuilder: (c, s) => _fadeScalePage(s, const UploadClipScreen())),
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
