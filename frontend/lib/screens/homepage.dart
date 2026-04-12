import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

void handleLogout(BuildContext context) {
  Navigator.pushReplacementNamed(context, '/login-page');
}

class _HomepageState extends State<Homepage> {
  int _selectedIndex = 0; // 0 = Home (active), 1 = Settings
  static const String _espWsUrl = 'ws://172.20.10.5:81';
  // Replace with your backend machine IP when running on phone.
  static const String _backendWsUrl = 'ws://192.168.56.1:8000/websocket/counts';
  static const double _maxBusWeightGrams = 4000.0;
  WebSocketChannel? _espChannel;
  WebSocketChannel? _backendChannel;
  bool _isEspConnected = false;
  bool _isBackendConnected = false;
  double _busWeightGrams = 0.0;
  double _frontPct = 0.0;
  double _backPct = 0.0;
  int _passengerCount = 0;

  // Brand Colors
  static const Color navyBlue = Color(0xFF1B3A6B);
  static const Color yellow = Color(0xFFFFCC00);
  static const Color routeBlue = Color(0xFF4A90D9);
  static const Color darkText = Color(0xFF1E2A3B);
  static const Color lightGray = Color(0xFFF5F6FA);

  // Dummy route data
  final List<Map<String, String>> _routes = [
    {
      'code': 'B001',
      'name': 'Parang - Cubao, via Molave',
      'distance': '421m away',
    },
  ];

  @override
  void initState() {
    super.initState();
    _connectEspWebSocket();
    _connectBackendWebSocket();
  }

  @override
  void dispose() {
    _espChannel?.sink.close();
    _backendChannel?.sink.close();
    super.dispose();
  }

  bool get _isOverweight => _busWeightGrams >= _maxBusWeightGrams;

  void _connectEspWebSocket() {
    try {
      _espChannel = WebSocketChannel.connect(Uri.parse(_espWsUrl));
      _espChannel!.stream.listen(
        (message) {
          final data = jsonDecode(message.toString());
          if (data is! Map<String, dynamic>) return;
          final type = data['type'];
          if (type != 'telemetry' && type != 'status') return;

          final rawWeight = data['weight_g'];
          final rawFrontPct = data['front_pct'];
          final rawBackPct = data['back_pct'];
          final weight = rawWeight is num
              ? rawWeight.toDouble()
              : double.tryParse('$rawWeight') ?? 0.0;

          if (!mounted) return;
          setState(() {
            _isEspConnected = true;
            _busWeightGrams = weight;
            _frontPct = rawFrontPct is num
                ? rawFrontPct.toDouble()
                : double.tryParse('$rawFrontPct') ?? 0.0;
            _backPct = rawBackPct is num
                ? rawBackPct.toDouble()
                : double.tryParse('$rawBackPct') ?? 0.0;
          });
        },
        onError: (_) {
          if (!mounted) return;
          setState(() => _isEspConnected = false);
        },
        onDone: () {
          if (!mounted) return;
          setState(() => _isEspConnected = false);
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isEspConnected = false);
    }
  }

  void _connectBackendWebSocket() {
    try {
      _backendChannel = WebSocketChannel.connect(Uri.parse(_backendWsUrl));
      _backendChannel!.stream.listen(
        (message) {
          final data = jsonDecode(message.toString());
          if (data is! Map<String, dynamic>) return;

          final rawTotal = data['total_passenger_counts'];
          if (!mounted) return;
          setState(() {
            _isBackendConnected = true;
            _passengerCount = rawTotal is int ? rawTotal : int.tryParse('$rawTotal') ?? 0;
          });
        },
        onError: (_) {
          if (!mounted) return;
          setState(() => _isBackendConnected = false);
          _retryBackendConnection();
        },
        onDone: () {
          if (!mounted) return;
          setState(() => _isBackendConnected = false);
          _retryBackendConnection();
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isBackendConnected = false);
      _retryBackendConnection();
    }
  }

  void _retryBackendConnection() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _connectBackendWebSocket();
    });
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
          // Route Title
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

          // Location Card
          _buildLocationCard(),

          const SizedBox(height: 16),
          _buildWeightStatusCard(),
          const SizedBox(height: 12),
          _buildDriverStatsCard(),

          const SizedBox(height: 28),

          // Biyahe Routes
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

          // Route List
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

  Widget _buildWeightStatusCard() {
    final statusColor = !_isEspConnected
        ? Colors.grey
        : (_isOverweight ? const Color(0xFFFF6B6B) : const Color(0xFF0FBF6A));
    final statusText = !_isEspConnected
        ? 'NO DATA'
        : (_isOverweight ? 'OVERWEIGHT' : 'NORMAL');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bus Weight Status',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: darkText,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Weight: ${_busWeightGrams.toStringAsFixed(1)} g',
            style: const TextStyle(fontSize: 13, color: Color(0xFF3D4558)),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor.withOpacity(0.4)),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverStatsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Driver Dashboard',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: darkText,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Passenger Count: $_passengerCount',
            style: const TextStyle(fontSize: 13, color: Color(0xFF3D4558)),
          ),
          const SizedBox(height: 4),
          Text(
            _isBackendConnected ? 'Passenger source: backend live' : 'Passenger source: backend offline',
            style: const TextStyle(fontSize: 11, color: Color(0xFF70798A)),
          ),
          const SizedBox(height: 8),
          Text(
            'Front Weight: ${_frontPct.toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 13, color: Color(0xFF3D4558)),
          ),
          const SizedBox(height: 4),
          Text(
            'Back Weight: ${_backPct.toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 13, color: Color(0xFF3D4558)),
          ),
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
          // Icon column with dotted line
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
              // Dotted line
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

          // Labels
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'My Current Location',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                  color: darkText,
                ),
              ),
              SizedBox(height: 24),
              Text(
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
          // Route Code Badge
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

          // Route Name & Distance
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

          // Passenger Count
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
          // Home Tab
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

          // Settings Tab
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

// Dotted line painter for the location card
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
