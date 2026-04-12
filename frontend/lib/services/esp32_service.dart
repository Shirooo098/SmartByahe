import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/weight_data.dart';

/// WebSocket client for ESP32 `esp32_flutter_bridge` telemetry.
class Esp32Service {
  WebSocketChannel? _channel;

  /// Raw stream of decoded JSON objects (any message shape).
  Stream<dynamic> connectRaw(Uri uri) {
    _channel?.sink.close();
    _channel = WebSocketChannel.connect(uri);
    return _channel!.stream.map((raw) {
      try {
        return jsonDecode(raw.toString());
      } catch (_) {
        return null;
      }
    }).where((e) => e != null);
  }

  /// Parsed [WeightData] for `type == telemetry` (or legacy `status`) messages only.
  Stream<WeightData> telemetry(Uri uri) {
    return connectRaw(uri).map((decoded) {
      if (decoded is! Map) return null;
      final m = Map<String, dynamic>.from(decoded);
      final t = m['type'];
      if (t != 'telemetry' && t != 'status') return null;
      try {
        return WeightData.fromJson(m);
      } catch (_) {
        return null;
      }
    }).where((w) => w != null).map((w) => w!);
  }

  Future<void> close() async {
    await _channel?.sink.close();
    _channel = null;
  }
}
