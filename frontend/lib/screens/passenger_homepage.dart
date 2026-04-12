import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

class PassengerHomepage extends StatefulWidget {
  const PassengerHomepage({super.key});

  @override
  State<PassengerHomepage> createState() => _PassengerHomepageState();
}

class _PassengerHomepageState extends State<PassengerHomepage> {
  static const Color navyBlue = Color(0xFF1B3A6B);
  static const Color yellow = Color(0xFFFFCC00);
  static const Color darkText = Color(0xFF1E2A3B);

  int _selectedIndex = 0;

  // ─── Logout ──────────────────────────────────────────────────────────────────

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out', style: TextStyle(fontFamily: 'monospace')),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Log Out',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) context.go('/');
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEEEEE),
      appBar: AppBar(
        backgroundColor: navyBlue,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(4),
              child: Image.asset(
                'assets/images/nobglogo.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.directions_bus, color: navyBlue, size: 30),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Smart-Biyahe',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
      body: _selectedIndex == 0 ? _buildHome() : _buildSettings(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ─── Home ────────────────────────────────────────────────────────────────────

  Widget _buildHome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PASSENGER_SIDE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: Color(0xFF70798A),
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 16),
          _card(
            child: const Center(
              child: Text(
                'Welcome, Passenger!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  color: darkText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Settings ────────────────────────────────────────────────────────────────

  Widget _buildSettings() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Settings',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: darkText,
            ),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('Log Out'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Shared card wrapper ──────────────────────────────────────────────────────

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  // ─── Bottom Nav ──────────────────────────────────────────────────────────────

  Widget _buildBottomNav() {
    return Container(
      height: 64,
      decoration: const BoxDecoration(color: navyBlue),
      child: Row(
        children: [
          _navItem(index: 0, icon: Icons.home_rounded, label: 'Home'),
          _navItem(index: 1, icon: Icons.settings_rounded, label: 'Settings'),
        ],
      ),
    );
  }

  Widget _navItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final active = _selectedIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedIndex = index),
        child: Container(
          color: active ? yellow : navyBlue,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: active ? navyBlue : Colors.white, size: 22),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: active ? navyBlue : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
