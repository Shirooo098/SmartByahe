import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class PassengerHomepage extends StatefulWidget {
  const PassengerHomepage({super.key});

  @override
  State<PassengerHomepage> createState() => _PassengerHomepageState();
}

class _PassengerHomepageState extends State<PassengerHomepage> {
  static const String _espWsUrl = 'ws://172.20.10.5:81';
  // Replace with your backend machine IP when running on phone.
  static const String _backendWsUrl = 'ws://192.168.56.1:8000/websocket/counts';
  WebSocketChannel? _espChannel;
  WebSocketChannel? _backendChannel;
  bool _isEspConnected = false;
  bool _isBackendConnected = false;
  int _passengerCount = 0;
  double _latitude = 0.0;
  double _longitude = 0.0;
  bool _gpsValid = false;

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

  void _connectEspWebSocket() {
    try {
      _espChannel = WebSocketChannel.connect(Uri.parse(_espWsUrl));
      _espChannel!.stream.listen(
        (message) {
          final data = jsonDecode(message.toString());
          if (data is! Map<String, dynamic>) return;
          final type = data['type'];
          if (type != 'telemetry' && type != 'status') return;

          final rawLat = data['latitude'];
          final rawLng = data['longitude'];
          final rawGpsValid = data['gps_valid'];

          if (!mounted) return;
          setState(() {
            _isEspConnected = true;
            _latitude = rawLat is num ? rawLat.toDouble() : double.tryParse('$rawLat') ?? 0.0;
            _longitude = rawLng is num ? rawLng.toDouble() : double.tryParse('$rawLng') ?? 0.0;
            _gpsValid = rawGpsValid == true;
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
      appBar: AppBar(
        title: const Text('Passenger Home'),
        backgroundColor: const Color(0xFF1B3A6B),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E5EC)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: (_isEspConnected && _isBackendConnected)
                        ? const Color(0xFF0FBF6A)
                        : const Color(0xFFFF6B6B),
                  ),
                  const SizedBox(width: 8),
                  Text((_isEspConnected && _isBackendConnected) ? 'LIVE DATA' : 'OFFLINE'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E5EC)),
              ),
              child: Column(
                children: [
                  const Text('PASSENGER COUNT', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(
                    '$_passengerCount',
                    style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isBackendConnected ? 'Source: backend live' : 'Source: backend offline',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF70798A)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E5EC)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('GPS TRACKER', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(_gpsValid
                      ? 'Lat: ${_latitude.toStringAsFixed(6)}'
                      : 'Lat: waiting for fix...'),
                  const SizedBox(height: 4),
                  Text(_gpsValid
                      ? 'Lng: ${_longitude.toStringAsFixed(6)}'
                      : 'Lng: waiting for fix...'),
                  const SizedBox(height: 4),
                  Text(
                    _isEspConnected ? 'Source: ESP32 live' : 'Source: ESP32 offline',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF70798A)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
