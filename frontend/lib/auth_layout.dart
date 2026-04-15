import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smartbyahe/screens/role_selection.dart';
// import 'screens/homepage.dart';

// import 'screens/landing_page.dart';
// import 'screens/passenger_detection_screen.dart';
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Still waiting for auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF1B3A6B),
            body: Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        }

        // User is logged in → go to Homepage
        // if (snapshot.hasData && snapshot.data != null) {
        //   return const Homepage();
        // }

        // Not authenticated → go to WelcomePage
        return const RoleSelectionPage();
      },
    );
  }
}
