import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'location_picker.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

void handleLogout(BuildContext context) {
  Navigator.pushReplacementNamed(context, '/login-page');
}

class _HomepageState extends State<Homepage> {
  int _selectedIndex = 0;

  static const Color navyBlue = Color(0xFF1B3A6B);
  static const Color yellow = Color(0xFFFFCC00);
  static const Color routeBlue = Color(0xFF4A90D9);
  static const Color darkText = Color(0xFF1E2A3B);

  String _currentLocationLabel = 'My Current Location';
  LatLng? _currentLatLng;

  final List<Map<String, String>> _routes = [
    {
      'code': 'B001',
      'name': 'Parang - Cubao, via Molave',
      'distance': '421m away',
    },
  ];

  Future<void> _openLocationPicker() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
    );

    if (result != null) {
      setState(() {
        _currentLatLng = result['latLng'] as LatLng;
        final fullAddress = result['address'] as String;
        final parts = fullAddress.split(',');
        _currentLocationLabel = parts.take(2).join(',').trim();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEEEEE),
      appBar: _buildAppBar(),
      body: _selectedIndex == 0 ? _buildHomeBody() : _buildSettingsBody(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
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
              errorBuilder: (context, error, stackTrace) =>
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
    );
  }

  Widget _buildHomeBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              'Route',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: routeBlue,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildLocationCard(),
          const SizedBox(height: 28),
          const Text(
            'Biyahe Routes',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: darkText,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 12),
          ...(_routes.map(
            (route) => _buildRouteCard(
              code: route['code']!,
              name: route['name']!,
              distance: route['distance']!,
              count: '10/12',
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon column
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.orange, width: 2.5),
                ),
              ),
              SizedBox(
                height: 32,
                child: CustomPaint(
                  painter: _DottedLinePainter(),
                  size: const Size(2, 32),
                ),
              ),
              const Icon(Icons.location_on, color: Colors.amber, size: 24),
            ],
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Tappable Current Location row ──────────────────────────
                GestureDetector(
                  onTap: _openLocationPicker,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _currentLocationLabel,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'monospace',
                            color: darkText,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.edit_location_alt_outlined,
                        size: 16,
                        color: Colors.orange,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                const Text(
                  'Destination',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                    color: darkText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard({
    required String code,
    required String name,
    required String distance,
    required String count,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: routeBlue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                code,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                    color: darkText,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  distance,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          Text(
            count,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: routeBlue,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsBody() {
    return const Center(
      child: Text(
        'Settings',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      height: 64,
      decoration: const BoxDecoration(color: navyBlue),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedIndex = 0),
              child: Container(
                color: _selectedIndex == 0 ? yellow : navyBlue,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.home_rounded,
                      color: _selectedIndex == 0 ? navyBlue : Colors.white,
                      size: 22,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Home',
                      style: TextStyle(
                        color: _selectedIndex == 0 ? navyBlue : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedIndex = 1),
              child: Container(
                color: _selectedIndex == 1 ? yellow : navyBlue,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.settings_rounded,
                      color: _selectedIndex == 1 ? navyBlue : Colors.white,
                      size: 22,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Settings',
                      style: TextStyle(
                        color: _selectedIndex == 1 ? navyBlue : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DottedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1.5;
    const dashHeight = 4.0;
    const dashSpace = 3.0;
    double startY = 0;
    while (startY < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, startY),
        Offset(size.width / 2, startY + dashHeight),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(_DottedLinePainter oldDelegate) => false;
}
