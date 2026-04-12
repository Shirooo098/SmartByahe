/// Parsed ESP32 WebSocket telemetry (`type: telemetry` from `esp32_flutter_bridge.ino`).
class WeightData {
  final double frontWeight;
  final double backWeight;
  final double totalWeight;
  final double frontPct;
  final double backPct;
  final String status;
  final double lat;
  final double lng;
  final double speedKmh;
  final int satellites;
  final bool gpsValid;
  final bool? frontReady;
  final bool? backReady;
  final bool? hasHx711Lib;

  const WeightData({
    required this.frontWeight,
    required this.backWeight,
    required this.totalWeight,
    required this.frontPct,
    required this.backPct,
    required this.status,
    required this.lat,
    required this.lng,
    required this.speedKmh,
    required this.satellites,
    required this.gpsValid,
    this.frontReady,
    this.backReady,
    this.hasHx711Lib,
  });

  bool get isOverload => status == 'OVERLOAD';
  bool get isImbalanceFront => status == 'IMBALANCE_FRONT';
  bool get isImbalanceBack => status == 'IMBALANCE_BACK';
  bool get isNormal => status == 'NORMAL';

  static double _num(dynamic v, [double fallback = 0.0]) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? fallback;
  }

  static int _int(dynamic v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? fallback;
  }

  static bool _bool(dynamic v) {
    if (v == true || v == 'true') return true;
    return false;
  }

  static bool? _boolOrNull(dynamic v) {
    if (v == null) return null;
    if (v == true || v == 'true') return true;
    if (v == false || v == 'false') return false;
    return null;
  }

  /// Accepts firmware JSON: snake_case telemetry plus optional camelCase aliases.
  factory WeightData.fromJson(Map<String, dynamic> j) {
    final total = _num(j['weight_g'] ?? j['totalWeight']);
    final front = _num(j['front_g'] ?? j['frontWeight']);
    final back = _num(j['back_g'] ?? j['backWeight']);
    final fp = _num(j['front_pct'] ?? j['frontPct']);
    final bp = _num(j['back_pct'] ?? j['backPct']);
    final lat = _num(j['latitude'] ?? j['lat'], 0.0);
    final lng = _num(j['longitude'] ?? j['lng'], 0.0);
    final speed = _num(j['speed_kmh'] ?? j['speed'], 0.0);
    final sats = _int(j['satellites'], 0);
    final rawStatus = j['status'];
    final status = rawStatus is String && rawStatus.isNotEmpty
        ? rawStatus
        : 'NORMAL';
    final gv = j['gps_valid'] ?? j['gpsValid'];
    final gpsValid = _bool(gv);

    return WeightData(
      frontWeight: front,
      backWeight: back,
      totalWeight: total,
      frontPct: fp,
      backPct: bp,
      status: status,
      lat: lat,
      lng: lng,
      speedKmh: speed,
      satellites: sats,
      gpsValid: gpsValid,
      frontReady: _boolOrNull(j['front_ready']),
      backReady: _boolOrNull(j['back_ready']),
      hasHx711Lib: _boolOrNull(j['has_hx711_lib']),
    );
  }
}
