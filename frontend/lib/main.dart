import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/landing_page.dart';
import 'screens/login_forms.dart';
import 'screens/register_forms.dart';
import 'screens/homepage.dart';
import 'auth_layout.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

final GoRouter _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const AuthLayout()),
    GoRoute(
      path: '/login-form',
      builder: (context, state) => const LoginFormScreen(),
    ),
    GoRoute(path: '/HomePage', builder: (context, state) => const Homepage()),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/login-page',
      builder: (context, state) => const LandingPage(),
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

class jcPage extends StatelessWidget {
  const jcPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: const Center(child: Text('Welcome to SmartByahe!')),
    );
  }
}
