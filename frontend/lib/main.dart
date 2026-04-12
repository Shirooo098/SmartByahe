import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'screens/landing_page.dart';
import 'screens/login_forms.dart';
import 'screens/register_forms.dart';
import 'screens/driver_homepage.dart';
import 'screens/passenger_homepage.dart';
import 'screens/passenger_detection_screen.dart';
import 'auth_layout.dart';
import 'screens/role_selection.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

// Protected routes — redirect to '/' if not logged in
const _protectedRoutes = [
  '/driver-home',
  '/passenger-home',
  '/passenger-detection',
  '/role-selection',
  '/HomePage',
];

final GoRouter _router = GoRouter(
  initialLocation: '/',
  refreshListenable: GoRouterRefreshStream(
    FirebaseAuth.instance.authStateChanges(),
  ),
  redirect: (context, state) {
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;
    final isProtected = _protectedRoutes.any(
      (r) => state.matchedLocation.startsWith(r),
    );

    if (!isLoggedIn && isProtected) return '/';
    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (context, state) => const AuthLayout()),
    GoRoute(
      path: '/login-form',
      builder: (context, state) {
        final role = state.extra as String? ?? 'passenger';
        return LoginFormScreen(role: role);
      },
    ),
    GoRoute(
      path: '/driver-home',
      builder: (context, state) => const DriverHomepage(),
    ),
    GoRoute(
      path: '/role-selection',
      builder: (context, state) => const RoleSelectionPage(),
    ),
    GoRoute(
      path: '/passenger-home',
      builder: (context, state) => const PassengerHomepage(),
    ),
    GoRoute(
      path: '/passenger-detection',
      builder: (context, state) => const PassengerDetectionScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) {
        final role = state.extra as String? ?? 'passenger';
        return RegisterScreen(role: role);
      },
    ),
    GoRoute(
      path: '/landing',
      builder: (context, state) {
        final role = state.extra as String? ?? 'passenger';
        return LandingPage(role: role);
      },
    ),
  ],
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B3A6B)),
        useMaterial3: true,
      ),
    );
  }
}

// Helper to make Firebase auth stream work with GoRouter's refreshListenable
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.listen((_) => notifyListeners());
  }

  late final dynamic _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
