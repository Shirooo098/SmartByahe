import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// PassengerDetectionScreen
/// Requires in pubspec.yaml:
///   web_socket_channel: ^2.4.0

class PassengerDetectionScreen extends StatefulWidget {
  const PassengerDetectionScreen({super.key});

  @override
  State<PassengerDetectionScreen> createState() =>
      _PassengerDetectionScreenState();
}

class _PassengerDetectionScreenState extends State<PassengerDetectionScreen>
    with SingleTickerProviderStateMixin {
  // ── WebSocket (ESP32 over hotspot Wi-Fi) ──────────────────────────────────
  // Replace with your ESP32 hotspot IP shown in Serial Monitor.
  static const String _wsUrl = 'ws://172.20.10.5:81';
  WebSocketChannel? _channel;
  bool _isConnected = false;
  double _busWeightGrams = 0.0;
  double _latitude = 0.0;
  double _longitude = 0.0;
  bool _gpsValid = false;
  static const double _maxBusWeightGrams = 4000.0;

  // ── Animation (pulse for detection indicator) ─────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // ── Data ─────────────────────────────────────────────────────────────────
  final Map<String, int> _classCounts = {
    'Child Male': 0,
    'Adult Male': 0,
    'Senior Male': 0,
    'Child Female': 0,
    'Adult Female': 0,
    'Senior Female': 0,
  };

  int get _totalPassengers =>
      _classCounts.values.fold(0, (sum, count) => sum + count);
  bool get _isOverweight => _busWeightGrams >= _maxBusWeightGrams;

  final String _carModel = 'Toyota Innova Zenix';

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _connectWebSocket();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _pulseController.dispose();
    super.dispose();
  }

  // ── WebSocket ─────────────────────────────────────────────────────────────
  void _connectWebSocket() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      setState(() => _isConnected = true);

      _channel!.stream.listen(
        (message) {
          _handleIncomingLine(message.toString());
        },
        onError: (error) {
          setState(() => _isConnected = false);
          _retryConnection();
        },
        onDone: () {
          setState(() => _isConnected = false);
          _retryConnection();
        },
      );
    } catch (e) {
      setState(() => _isConnected = false);
      _retryConnection();
    }
  }

  void _handleIncomingLine(String line) {
    try {
      final data = jsonDecode(line);
      if (data is! Map<String, dynamic>) return;
      final type = data['type'];
      if (type != 'telemetry' && type != 'status') return;

      final rawCount = data['passenger_count'];
      final total = rawCount is int ? rawCount : int.tryParse('$rawCount') ?? 0;
      final rawWeight = data['weight_g'];
      final rawLat = data['latitude'];
      final rawLng = data['longitude'];
      final rawGpsValid = data['gps_valid'];
      setState(() {
        _isConnected = true;
        _classCounts['Child Male'] = 0;
        _classCounts['Adult Male'] = total;
        _classCounts['Senior Male'] = 0;
        _classCounts['Child Female'] = 0;
        _classCounts['Adult Female'] = 0;
        _classCounts['Senior Female'] = 0;
        _busWeightGrams = rawWeight is num
            ? rawWeight.toDouble()
            : double.tryParse('$rawWeight') ?? 0.0;
        _latitude = rawLat is num ? rawLat.toDouble() : double.tryParse('$rawLat') ?? 0.0;
        _longitude = rawLng is num ? rawLng.toDouble() : double.tryParse('$rawLng') ?? 0.0;
        _gpsValid = rawGpsValid == true;
      });
    } catch (_) {
      // Ignore malformed lines from serial stream.
    }
  }

  void _retryConnection() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _connectWebSocket();
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: SafeArea(
        child: Column(
          children: [
            _buildCarModelFrame(),
            Expanded(child: _buildDetectionStatusFrame()),
            _buildStatsFrame(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Frame 1 — Car Model
  // ---------------------------------------------------------------------------
  Widget _buildCarModelFrame() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF161A23),
        border: Border(bottom: BorderSide(color: Color(0xFF2A2F3D), width: 1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF1E5CF6).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.directions_car_rounded,
              color: Color(0xFF4D8BFF),
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'VEHICLE MODEL',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8,
                    color: Color(0xFF5A6275),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _carModel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE8EAF0),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          // Connection badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color:
                  (_isConnected
                          ? const Color(0xFF0FBF6A)
                          : const Color(0xFFFF4444))
                      .withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color:
                    (_isConnected
                            ? const Color(0xFF0FBF6A)
                            : const Color(0xFFFF4444))
                        .withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _isConnected
                        ? const Color(0xFF0FBF6A)
                        : const Color(0xFFFF4444),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  _isConnected ? 'LIVE' : 'OFF',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _isConnected
                        ? const Color(0xFF0FBF6A)
                        : const Color(0xFFFF4444),
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Frame 2 — Detection Status
  // ---------------------------------------------------------------------------
  Widget _buildDetectionStatusFrame() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF0D0F14),
      child: _isConnected ? _buildActiveDetection() : _buildOfflineStatus(),
    );
  }

  Widget _buildActiveDetection() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 140 * _pulseAnimation.value,
                    height: 140 * _pulseAnimation.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(
                          0xFF0FBF6A,
                        ).withOpacity(0.15 * _pulseAnimation.value),
                        width: 1.5,
                      ),
                    ),
                  ),
                  Container(
                    width: 100 * _pulseAnimation.value,
                    height: 100 * _pulseAnimation.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(
                          0xFF0FBF6A,
                        ).withOpacity(0.25 * _pulseAnimation.value),
                        width: 1.5,
                      ),
                    ),
                  ),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0FBF6A).withOpacity(0.1),
                      border: Border.all(
                        color: const Color(0xFF0FBF6A).withOpacity(0.6),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.sensors_rounded,
                      color: Color(0xFF0FBF6A),
                      size: 28,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'DETECTION ACTIVE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.5,
              color: Color(0xFF0FBF6A),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Receiving live counts from ESP32 WebSocket',
            style: TextStyle(fontSize: 12, color: Color(0xFF5A6275)),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF161A23),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2A2F3D)),
            ),
            child: Column(
              children: [
                const Text(
                  'PASSENGERS DETECTED',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8,
                    color: Color(0xFF5A6275),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_totalPassengers',
                  style: const TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF4D8BFF),
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF161A23),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2A2F3D)),
            ),
            child: Column(
              children: [
                Text(
                  'Bus Weight: ${_busWeightGrams.toStringAsFixed(1)} g',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE8EAF0),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _gpsValid
                      ? 'GPS: ${_latitude.toStringAsFixed(6)}, ${_longitude.toStringAsFixed(6)}'
                      : 'GPS: Waiting for fix...',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF5A6275)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: (_isOverweight
                      ? const Color(0xFFFF6B6B)
                      : const Color(0xFF0FBF6A))
                  .withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (_isOverweight
                        ? const Color(0xFFFF6B6B)
                        : const Color(0xFF0FBF6A))
                    .withOpacity(0.45),
              ),
            ),
            child: Column(
              children: [
                const Text(
                  'WEIGHT STATUS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: Color(0xFFB8BFCC),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _isOverweight ? 'OVERWEIGHT' : 'NORMAL',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: _isOverweight
                        ? const Color(0xFFFF6B6B)
                        : const Color(0xFF0FBF6A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineStatus() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFF4444).withOpacity(0.1),
              border: Border.all(
                color: const Color(0xFFFF4444).withOpacity(0.4),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.sensors_off_rounded,
              color: Color(0xFFFF6B6B),
              size: 28,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'ESP32 OFFLINE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.5,
              color: Color(0xFFFF6B6B),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Connect phone + ESP32 to same hotspot network',
            style: TextStyle(fontSize: 12, color: Color(0xFF5A6275)),
          ),
          const SizedBox(height: 4),
          const Text(
            'Set _wsUrl to ws://<esp32-ip>:81',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF3D4558),
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Retrying connection...',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF5A6275),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Frame 3 — Stats + Class Table
  // ---------------------------------------------------------------------------
  Widget _buildStatsFrame() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF161A23),
        border: Border(top: BorderSide(color: Color(0xFF2A2F3D), width: 1)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: const [
                Expanded(
                  child: Text(
                    'CLASS',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                      color: Color(0xFF3D4558),
                    ),
                  ),
                ),
                Text(
                  'COUNT',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                    color: Color(0xFF3D4558),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: _classCounts.entries.map((entry) {
                return _buildClassRow(entry.key, entry.value);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassRow(String className, int count) {
    final isMale = className.toLowerCase().contains('male');
    final accentColor = isMale
        ? const Color(0xFF4D8BFF)
        : const Color(0xFFFF6BB3);
    final bgColor = isMale
        ? const Color(0xFF1E5CF6).withOpacity(0.06)
        : const Color(0xFFE91E8C).withOpacity(0.06);

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentColor.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Icon(
            isMale ? Icons.male_rounded : Icons.female_rounded,
            color: accentColor.withOpacity(0.7),
            size: 14,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              className,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFFB8BFCC),
                letterSpacing: 0.2,
              ),
            ),
          ),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: count > 0 ? accentColor : const Color(0xFF3D4558),
            ),
          ),
        ],
      ),
    );
  }
}
