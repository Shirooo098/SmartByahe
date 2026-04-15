import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as latlng;

class PassengerRouteDetailScreen extends StatefulWidget {
  const PassengerRouteDetailScreen({
    super.key,
    required this.tripId,
    required this.routeCode,
    required this.routeName,
  });

  final String tripId;
  final String routeCode;
  final String routeName;

  @override
  State<PassengerRouteDetailScreen> createState() =>
      _PassengerRouteDetailScreenState();
}

class _PassengerRouteDetailScreenState extends State<PassengerRouteDetailScreen> {
  static const Color navyBlue = Color(0xFF1B3A6B);
  static const Color yellow = Color(0xFFFFCC00);
  static const Color panelYellow = Color(0xFFF8D648);

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _tripSubscription;
  final fmap.MapController _webMapController = fmap.MapController();

  bool _tripGpsValid = false;
  double _busLat = 14.5995;
  double _busLng = 120.9842;
  int _passengerCount = 0;
  int _maxCapacity = 12;
  String _routeName = '';
  String _routeCode = 'B001';
  String _tripPhase = 'UNKNOWN';
  double _distToFinishM = -1.0;

  int _childMale = 0;
  int _adultMale = 0;
  int _seniorMale = 0;
  int _childFemale = 0;
  int _adultFemale = 0;
  int _seniorFemale = 0;

  @override
  void initState() {
    super.initState();
    _routeName = widget.routeName;
    _routeCode = widget.routeCode;

    _tripSubscription = FirebaseFirestore.instance
        .collection('trips')
        .doc(widget.tripId)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      if (!mounted || data == null) return;

      final breakdown = data['passengerBreakdown'];
      final breakdownMap = breakdown is Map
          ? Map<String, dynamic>.from(breakdown)
          : <String, dynamic>{};

      setState(() {
        _routeName = (data['routeName'] as String?)?.trim().isNotEmpty == true
            ? data['routeName'] as String
            : _routeName;
        _routeCode = (data['routeCode'] as String?)?.trim().isNotEmpty == true
            ? data['routeCode'] as String
            : _routeCode;

        _tripGpsValid = data['gpsValid'] == true;
        _busLat = data['currentLat'] is num
            ? (data['currentLat'] as num).toDouble()
            : _busLat;
        _busLng = data['currentLng'] is num
            ? (data['currentLng'] as num).toDouble()
            : _busLng;
        _tripPhase = (data['tripPhase'] as String?)?.trim().isNotEmpty == true
          ? data['tripPhase'] as String
          : _tripPhase;
        _distToFinishM = data['distToFinishM'] is num
          ? (data['distToFinishM'] as num).toDouble()
          : _distToFinishM;

        _maxCapacity = _asInt(data['maxCapacity'], fallback: 12);
        _passengerCount = _asInt(data['passengerCount']);

        _childMale = _asInt(
          breakdownMap['childMale'] ?? data['childMale'] ?? data['child_male'],
        );
        _adultMale = _asInt(
          breakdownMap['adultMale'] ?? data['adultMale'] ?? data['adult_male'],
        );
        _seniorMale = _asInt(
          breakdownMap['seniorMale'] ?? data['seniorMale'] ?? data['senior_male'],
        );
        _childFemale = _asInt(
          breakdownMap['childFemale'] ??
              data['childFemale'] ??
              data['child_female'],
        );
        _adultFemale = _asInt(
          breakdownMap['adultFemale'] ??
              data['adultFemale'] ??
              data['adult_female'],
        );
        _seniorFemale = _asInt(
          breakdownMap['seniorFemale'] ??
              data['seniorFemale'] ??
              data['senior_female'],
        );
      });

      if (_tripGpsValid) {
        try {
          _webMapController.move(latlng.LatLng(_busLat, _busLng), 15);
        } catch (_) {
          // Ignore move calls before map attach.
        }
      }
    });
  }

  @override
  void dispose() {
    _tripSubscription?.cancel();
    super.dispose();
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }

  String _phaseLabel() {
    switch (_tripPhase) {
      case 'AT_START':
        return 'At Start Terminal';
      case 'DEPARTED_START':
        return 'Departed Start Terminal';
      case 'EN_ROUTE':
        return 'En route';
      case 'ARRIVED_FINISH':
        return 'Arrived at Finish Terminal';
      default:
        return 'Waiting for geofence state';
    }
  }

  Color _phaseColor() {
    switch (_tripPhase) {
      case 'AT_START':
        return Colors.amber.shade800;
      case 'DEPARTED_START':
        return const Color(0xFF2D8CFF);
      case 'EN_ROUTE':
        return const Color(0xFF2E62AE);
      case 'ARRIVED_FINISH':
        return const Color(0xFF0FBF6A);
      default:
        return const Color(0xFF5A6275);
    }
  }

  String _distanceLabel() {
    if (_distToFinishM < 0) return 'Distance unavailable';
    if (_distToFinishM >= 1000) {
      return '${(_distToFinishM / 1000).toStringAsFixed(2)} km to finish';
    }
    return '${_distToFinishM.toStringAsFixed(0)} m to finish';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE4E4E4),
      appBar: AppBar(
        backgroundColor: navyBlue,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Row(
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
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _tripGpsValid
                          ? (kIsWeb
                              ? fmap.FlutterMap(
                                  mapController: _webMapController,
                                  options: fmap.MapOptions(
                                    initialCenter: latlng.LatLng(_busLat, _busLng),
                                    initialZoom: 15,
                                  ),
                                  children: [
                                    fmap.TileLayer(
                                      urlTemplate:
                                          'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      subdomains: const ['a', 'b', 'c'],
                                      userAgentPackageName: 'com.smartbiyahe.app',
                                    ),
                                    fmap.MarkerLayer(
                                      markers: [
                                        fmap.Marker(
                                          point: latlng.LatLng(_busLat, _busLng),
                                          width: 52,
                                          height: 52,
                                          child: const Icon(
                                            Icons.directions_bus,
                                            color: navyBlue,
                                            size: 34,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                              : fmap.FlutterMap(
                                  mapController: _webMapController,
                                  options: fmap.MapOptions(
                                    initialCenter: latlng.LatLng(_busLat, _busLng),
                                    initialZoom: 15,
                                  ),
                                  children: [
                                    fmap.TileLayer(
                                      urlTemplate:
                                          'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      subdomains: const ['a', 'b', 'c'],
                                      userAgentPackageName: 'com.smartbiyahe.app',
                                    ),
                                    fmap.MarkerLayer(
                                      markers: [
                                        fmap.Marker(
                                          point: latlng.LatLng(_busLat, _busLng),
                                          width: 52,
                                          height: 52,
                                          child: const Icon(
                                            Icons.directions_bus,
                                            color: navyBlue,
                                            size: 34,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ))
                          : Container(
                              color: const Color(0xFFD9DBDE),
                              alignment: Alignment.center,
                              child: const Text(
                                'Waiting for live bus GPS location...',
                                style: TextStyle(
                                  color: Color(0xFF5A6275),
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: navyBlue.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: const BoxDecoration(
                                color: Color(0xFF7DA8FF),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  _routeCode,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _routeName,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'monospace',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${_phaseLabel()} · ${_distanceLabel()}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'monospace',
                                      color: _phaseColor(),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: _phaseColor().withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _tripPhase,
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'monospace',
                                  color: _phaseColor(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: navyBlue,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Passengers',
                    style: TextStyle(
                      color: yellow,
                      fontSize: 30,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    '$_passengerCount/$_maxCapacity',
                    style: const TextStyle(
                      color: yellow,
                      fontSize: 28,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.35,
              children: [
                _breakdownTile('Child Male', _childMale),
                _breakdownTile('Adult Male', _adultMale),
                _breakdownTile('Senior Male', _seniorMale),
                _breakdownTile('Child Female', _childFemale),
                _breakdownTile('Adult Female', _adultFemale),
                _breakdownTile('Senior Female', _seniorFemale),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _breakdownTile(String label, int value) {
    return Container(
      decoration: BoxDecoration(
        color: panelYellow,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: navyBlue.withValues(alpha: 0.5)),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF374151),
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: navyBlue,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
