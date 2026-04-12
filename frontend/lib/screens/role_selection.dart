import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class RoleSelectionPage extends StatelessWidget {
  const RoleSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            children: [
              const Spacer(flex: 2),

              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: const Color(0xFF1B3A6B),
                  borderRadius: BorderRadius.circular(28),
                ),
                padding: const EdgeInsets.all(12),
                child: Image.asset(
                  'assets/images/smart_byahe_logo.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.directions_bus,
                    color: Colors.white,
                    size: 100,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                'The Future of the Filipino Journey.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),

              const Spacer(flex: 2),

              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton(
                      onPressed: () =>
                          context.push('/landing', extra: 'driver'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1B3A6B),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Driver',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: OutlinedButton(
                      onPressed: () =>
                          context.push('/landing', extra: 'passenger'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black87,
                        side: const BorderSide(color: Colors.black38),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Passenger',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const Spacer(flex: 3),

              const Text(
                'By signing in or registering, you agree to the terms\nof service and privacy policy.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.black45),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
