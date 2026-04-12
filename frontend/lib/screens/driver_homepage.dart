import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/weight_data.dart';
import '../services/esp32_service.dart';

/// Driver dashboard: route, passengers, weight status, GPS map, camera placeholder, IoT status.
class DriverHomepage extends StatefulWidget {
  const DriverHomepage({super.key});

  @override
  State<DriverHomepage> createState() => _DriverHomepageState();
}

class _DriverHomepageState extends State<DriverHomepage> {
  int _selectedIndex = 0;

  /// Default ESP32 WebSocket — use Serial Monitor IP, or `ws://192.168.43.100:81` if you enable static IP on ESP32.
  static const String _defaultEspWsUrl = 'ws://192.168.4.1:81';

  /// Python / passenger-count server (VirtualBox host-only is often 192.168.56.1).
  /// Empty on **Flutter Web** — browsers will refuse or spam errors if no server is running.
  /// On Android/iOS/desktop, set to your server URL when you run the backend.
  late final String _backendWsUrl = kIsWeb
      ? ''
      : 'ws://192.168.56.1:8000/websocket/counts';
  static const double _maxBusWeightGrams = 4000.0;
  /// Seating capacity for display as "current / max".
  static const int _maxPassengerCapacity = 22;

  static const Color navyBlue = Color(0xFF1B3A6B);
  static const Color yellow = Color(0xFFFFCC00);
  static const Color routeBlue = Color(0xFF4A90D9);
  static const Color darkText = Color(0xFF1E2A3B);

  final Esp32Service _esp32Service = Esp32Service();
  StreamSubscription<WeightData>? _espTelemetrySub;
  Timer? _espRetryTimer;
  WebSocketChannel? _backendChannel;
  StreamSubscription<dynamic>? _backendSub;
  String _espWsUrl = _defaultEspWsUrl;
  final TextEditingController _espUrlController = TextEditingController();
  bool _isEspConnected = false;
  bool _isBackendConnected = false;
  WeightData? _espTelemetry;
  int _passengerCount = 0;

  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _espUrlController.text = _espWsUrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_connectEspWebSocketAsync());
    });
    if (_backendWsUrl.isNotEmpty) {
      _connectBackendWebSocket();
    }
  }

  @override
  void dispose() {
    _espRetryTimer?.cancel();
    unawaited(_espTelemetrySub?.cancel());
    unawaited(_esp32Service.close());
    unawaited(_backendSub?.cancel());
    _backendChannel?.sink.close();
    _espUrlController.dispose();
    super.dispose();
  }

  double get _busWeightGrams => _espTelemetry?.totalWeight ?? 0.0;

  double get _latitude => _espTelemetry?.lat ?? 14.5995;

  double get _longitude => _espTelemetry?.lng ?? 120.9842;

  bool get _gpsValid => _espTelemetry?.gpsValid ?? false;

  /// HX711 DOUT ready flags from firmware (when present).
  bool get _loadSensorHardwareActive {
    if (!_isEspConnected) return false;
    final d = _espTelemetry;
    if (d == null) return true;
    if (d.hasHx711Lib == false) return false;
    if (d.frontReady == null && d.backReady == null) return true;
    return (d.frontReady == true) || (d.backReady == true);
  }

  bool get _canShowGoogleMap =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Color _loadStatusColor() {
    final d = _espTelemetry;
    if (!_isEspConnected || d == null) return Colors.grey;
    if (d.isOverload) return const Color(0xFFFF6B6B);
    if (d.isImbalanceFront || d.isImbalanceBack) return Colors.orange;
    return const Color(0xFF0FBF6A);
  }

  String _loadStatusLabel() {
    final d = _espTelemetry;
    if (!_isEspConnected || d == null) return '—';
    switch (d.status) {
      case 'OVERLOAD':
        return 'OVERLOAD';
      case 'IMBALANCE_FRONT':
        return 'IMBALANCE · FRONT';
      case 'IMBALANCE_BACK':
        return 'IMBALANCE · BACK';
      default:
        return 'NORMAL';
    }
  }

  /// Reconnects to ESP32. Prefer [explicitUrl] (e.g. text field) so state cannot lag behind what you typed.
  Future<void> _connectEspWebSocketAsync({String? explicitUrl}) async {
    _espRetryTimer?.cancel();
    _espRetryTimer = null;

    final rawUrl = (explicitUrl ?? _espUrlController.text).trim();
    final urlToUse = rawUrl.isNotEmpty ? rawUrl : _espWsUrl;

    final uri = Uri.tryParse(urlToUse);
    if (uri == null ||
        (uri.scheme != 'ws' && uri.scheme != 'wss') ||
        uri.host.isEmpty) {
      if (mounted) {
        setState(() {
          _isEspConnected = false;
          _espTelemetry = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Invalid WebSocket URL. Use ws://IP:81 (example: ws://192.168.1.50:81)',
            ),
          ),
        );
      }
      return;
    }

    try {
      await _espTelemetrySub?.cancel();
      _espTelemetrySub = null;
      await _esp32Service.close();

      if (!mounted) return;
      setState(() {
        _espWsUrl = urlToUse;
        _espUrlController.text = urlToUse;
        _isEspConnected = false;
        _espTelemetry = null;
      });

      _espTelemetrySub = _esp32Service.telemetry(uri).listen(
        (d) {
          if (!mounted) return;
          setState(() {
            _isEspConnected = true;
            _espTelemetry = d;
          });
          if (d.gpsValid && _mapController != null) {
            _mapController!.animateCamera(
              CameraUpdate.newLatLng(LatLng(d.lat, d.lng)),
            );
          }
        },
        onError: (Object e) {
          if (!mounted) return;
          setState(() {
            _isEspConnected = false;
            _espTelemetry = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'ESP32 WebSocket error: $e',
              ),
            ),
          );
          _scheduleEspRetry();
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _isEspConnected = false;
            _espTelemetry = null;
          });
          _scheduleEspRetry();
        },
        cancelOnError: true,
      );
    } catch (e, _) {
      if (!mounted) return;
      setState(() {
        _isEspConnected = false;
        _espTelemetry = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open WebSocket: $e')),
      );
      _scheduleEspRetry();
    }
  }

  void _scheduleEspRetry() {
    _espRetryTimer?.cancel();
    _espRetryTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) unawaited(_connectEspWebSocketAsync());
    });
  }

  Future<void> _applyEspUrl() async {
    FocusScope.of(context).unfocus();
    final next = _espUrlController.text.trim();
    if (next.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a WebSocket URL first.')),
      );
      return;
    }
    await _connectEspWebSocketAsync(explicitUrl: next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Reconnecting to $next. Status turns green when JSON telemetry arrives (~1s).',
        ),
      ),
    );
  }

  void _connectBackendWebSocket() {
    if (_backendWsUrl.isEmpty) {
      if (mounted) setState(() => _isBackendConnected = false);
      return;
    }
    try {
      unawaited(_backendSub?.cancel());
      _backendSub = null;
      _backendChannel?.sink.close();

      final uri = Uri.tryParse(_backendWsUrl);
      if (uri == null ||
          (uri.scheme != 'ws' && uri.scheme != 'wss') ||
          uri.host.isEmpty) {
        if (mounted) setState(() => _isBackendConnected = false);
        return;
      }

      _backendChannel = WebSocketChannel.connect(uri);
      _backendSub = _backendChannel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message.toString());
            if (data is! Map<String, dynamic>) return;
            final rawTotal = data['total_passenger_counts'];
            if (!mounted) return;
            setState(() {
              _isBackendConnected = true;
              _passengerCount =
                  rawTotal is int ? rawTotal : int.tryParse('$rawTotal') ?? 0;
            });
          } catch (_) {
            // Ignore malformed frames
          }
        },
        onError: (_) {
          if (!mounted) return;
          setState(() => _isBackendConnected = false);
          _retryBackend();
        },
        onDone: () {
          if (!mounted) return;
          setState(() => _isBackendConnected = false);
          _retryBackend();
        },
        cancelOnError: true,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isBackendConnected = false);
      _retryBackend();
    }
  }

  void _retryBackend() {
    if (_backendWsUrl.isEmpty) return;
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _backendWsUrl.isNotEmpty) {
        _connectBackendWebSocket();
      }
    });
  }

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
      ),
      body: _selectedIndex == 0 ? _buildDriverHome() : _buildSettings(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildDriverHome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DRIVER_SIDE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: Color(0xFF70798A),
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Active Route: Parang -> Cubao via Molave',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: routeBlue,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 12),
          _buildRouteCard(),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildPassengersCard()),
              const SizedBox(width: 12),
              Expanded(child: _buildWeightCard()),
            ],
          ),
          const SizedBox(height: 12),
          _buildDriverTelemetrySummaryCard(),
          const SizedBox(height: 12),
          _buildSpeedSatellitesRow(),
          const SizedBox(height: 16),
          _buildGpsSection(),
          const SizedBox(height: 16),
          _buildCameraSection(),
          const SizedBox(height: 20),
          const Text(
            'IOT STATUS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              fontFamily: 'monospace',
              color: darkText,
            ),
          ),
          const SizedBox(height: 10),
          _buildIotRow(),
        ],
      ),
    );
  }

  Widget _buildRouteCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: yellow,
                ),
              ),
              SizedBox(
                height: 36,
                child: CustomPaint(
                  painter: _DashedLinePainter(),
                  size: const Size(2, 36),
                ),
              ),
              const Icon(Icons.location_on, color: yellow, size: 22),
            ],
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Parang Terminal',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                    color: darkText,
                  ),
                ),
                SizedBox(height: 28),
                Text(
                  'Cubao Terminal',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
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

  Widget _buildPassengersCard() {
    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Passengers',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$_passengerCount / $_maxPassengerCapacity',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: navyBlue,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeightCard() {
    final status = _loadStatusLabel();
    final statusColor = _loadStatusColor();

    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weight Load',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_busWeightGrams.toStringAsFixed(0)} g',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: navyBlue,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            'Limit ${_maxBusWeightGrams.toStringAsFixed(0)} g',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
              fontFamily: 'monospace',
            ),
          ),
          if (_isEspConnected && _espTelemetry != null) ...[
            const SizedBox(height: 6),
            Text(
              'Front ${_espTelemetry!.frontWeight.toStringAsFixed(0)} g · Back ${_espTelemetry!.backWeight.toStringAsFixed(0)} g',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade700,
                fontFamily: 'monospace',
              ),
            ),
            Text(
              'Split ${_espTelemetry!.frontPct.toStringAsFixed(0)}% / ${_espTelemetry!.backPct.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade700,
                fontFamily: 'monospace',
              ),
            ),
          ],
          const SizedBox(height: 6),
          Center(
            child: Text(
              status,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: statusColor,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverTelemetrySummaryCard() {
    return Container(
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
      child: _espTelemetry == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Driver Telemetry',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Waiting for ESP32 telemetry…',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Connect to the correct ESP32 WebSocket URL to begin receiving weight and GPS data.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Driver Telemetry',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _telemetryValueTile(
                        title: 'Total Weight',
                        value: '${_busWeightGrams.toStringAsFixed(0)} g',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _telemetryValueTile(
                        title: 'Status',
                        value: _loadStatusLabel(),
                        valueColor: _loadStatusColor(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _telemetryValueTile(
                        title: 'Front Load',
                        value: '${_espTelemetry!.frontWeight.toStringAsFixed(0)} g',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _telemetryValueTile(
                        title: 'Back Load',
                        value: '${_espTelemetry!.backWeight.toStringAsFixed(0)} g',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _telemetryValueTile(
                  title: 'GPS',
                  value: _gpsValid
                      ? 'Lat ${_latitude.toStringAsFixed(5)}\nLng ${_longitude.toStringAsFixed(5)}'
                      : 'Waiting for GPS fix',
                  valueStyle: const TextStyle(height: 1.4),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _telemetryValueTile(
                        title: 'Satellites',
                        value: '${_espTelemetry!.satellites}',
                        valueColor: _espTelemetry!.satellites > 3
                            ? const Color(0xFF0FBF6A)
                            : Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _telemetryValueTile(
                        title: 'Speed',
                        value: '${_espTelemetry!.speedKmh.toStringAsFixed(1)} km/h',
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _telemetryValueTile({
    required String title,
    required String value,
    Color? valueColor,
    TextStyle? valueStyle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: valueStyle ?? TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: valueColor ?? darkText,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedSatellitesRow() {
    if (!_isEspConnected || _espTelemetry == null) {
      return const SizedBox.shrink();
    }
    final d = _espTelemetry!;
    return Row(
      children: [
        Expanded(
          child: _metricTile(
            icon: Icons.speed,
            title: 'Speed',
            value: '${d.speedKmh.toStringAsFixed(1)} km/h',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _metricTile(
            icon: Icons.satellite_alt,
            title: 'Satellites',
            value: '${d.satellites}',
            valueColor: d.satellites > 3 ? const Color(0xFF0FBF6A) : Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _metricTile({
    required IconData icon,
    required String title,
    required String value,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
      child: Row(
        children: [
          Icon(icon, color: routeBlue, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                    color: valueColor ?? darkText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGpsSection() {
    return Container(
      height: 180,
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
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: _canShowGoogleMap && _gpsValid
                ? GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(_latitude, _longitude),
                      zoom: 15,
                    ),
                    markers: {
                      Marker(
                        markerId: const MarkerId('bus'),
                        position: LatLng(_latitude, _longitude),
                      ),
                    },
                    onMapCreated: (c) {
                      _mapController = c;
                      if (_gpsValid) {
                        c.animateCamera(
                          CameraUpdate.newLatLng(LatLng(_latitude, _longitude)),
                        );
                      }
                    },
                    zoomControlsEnabled: false,
                    myLocationButtonEnabled: false,
                  )
                : Container(
                    color: const Color(0xFFE8ECF0),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _gpsValid
                              ? 'Lat ${_latitude.toStringAsFixed(5)}\nLng ${_longitude.toStringAsFixed(5)}'
                              : 'Waiting for GPS fix from ESP32…',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFF5A6275),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          Positioned(
            left: 12,
            top: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'GPS LOCATION',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                    color: darkText,
                    shadows: [
                      Shadow(
                        color: Colors.white,
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                Text(
                  'GY-NEO6MV2 · u-blox NEO-6M',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                    color: darkText.withValues(alpha: 0.75),
                    shadows: [
                      Shadow(
                        color: Colors.white,
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraSection() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Camera view — connect stream here')),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'View Camera',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  color: darkText,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  '- Press to view the Camera -',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIotRow() {
    return Row(
      children: [
        Expanded(
          child: _iotTile(
            icon: Icons.location_on_outlined,
            label: 'GPS',
            active: _isEspConnected && _gpsValid,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _iotTile(
            icon: Icons.videocam_outlined,
            label: 'Camera',
            active: _isBackendConnected,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _iotTile(
            icon: Icons.scale_outlined,
            label: 'Load Sensor',
            active: _loadSensorHardwareActive,
          ),
        ),
      ],
    );
  }

  Widget _iotTile({
    required IconData icon,
    required String label,
    required bool active,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: navyBlue,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white70, size: 22),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            active ? 'ACTIVE' : 'OFF',
            style: TextStyle(
              color: active ? const Color(0xFF0FBF6A) : Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettings() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ESP32 WebSocket',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: darkText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Use the IP printed in Serial Monitor after Wi‑Fi connects (e.g. ws://192.168.43.12:81). Phone and ESP32 must be on the same network.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _espUrlController,
            decoration: const InputDecoration(
              labelText: 'WebSocket URL',
              hintText: 'ws://192.168.x.x:81',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _applyEspUrl,
            child: const Text('Connect'),
          ),
          const SizedBox(height: 8),
          Text(
            _isEspConnected
                ? 'ESP32: receiving telemetry'
                : 'ESP32: no telemetry yet (wrong URL, firewall, or ESP off)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _isEspConnected
                  ? const Color(0xFF0FBF6A)
                  : Colors.grey.shade600,
              fontFamily: 'monospace',
            ),
          ),
        ],
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

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1.5;
    const dash = 4.0;
    const gap = 3.0;
    double y = 0;
    final cx = size.width / 2;
    while (y < size.height) {
      canvas.drawLine(Offset(cx, y), Offset(cx, y + dash), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
