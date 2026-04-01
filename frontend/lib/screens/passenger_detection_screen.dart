import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

/// PassengerDetectionScreen
/// Requires these packages in pubspec.yaml:
///   camera: ^0.11.0+2
///
/// Also add to AndroidManifest.xml:
///   <uses-permission android:name="android.permission.CAMERA" />
///
/// And to Info.plist (iOS):
///   <key>NSCameraUsageDescription</key>
///   <string>Camera is needed to detect passengers.</string>

class PassengerDetectionScreen extends StatefulWidget {
  const PassengerDetectionScreen({super.key});

  @override
  State<PassengerDetectionScreen> createState() =>
      _PassengerDetectionScreenState();
}

class _PassengerDetectionScreenState extends State<PassengerDetectionScreen> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  bool _isCameraError = false;

  // Passenger counts per class
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

  // Car model (placeholder — replace with your actual detection logic)
  String _carModel = 'Toyota Innova Zenix';

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _isCameraError = true);
        return;
      }
      _cameraController = CameraController(
        _cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _isCameraInitialized = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCameraError = true);
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  void _incrementClass(String className) {
    setState(
      () => _classCounts[className] = (_classCounts[className] ?? 0) + 1,
    );
  }

  void _decrementClass(String className) {
    setState(() {
      if ((_classCounts[className] ?? 0) > 0) {
        _classCounts[className] = _classCounts[className]! - 1;
      }
    });
  }

  void _resetAll() {
    setState(() {
      for (final key in _classCounts.keys) {
        _classCounts[key] = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: SafeArea(
        child: Column(
          children: [
            // ── FRAME 1: Car Model ──────────────────────────────────
            _buildCarModelFrame(),

            // ── FRAME 2: Camera Feed ────────────────────────────────
            Expanded(child: _buildCameraFrame()),

            // ── FRAME 3: Stats + Class Table ───────────────────────
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
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF0FBF6A).withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF0FBF6A).withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF0FBF6A),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                const Text(
                  'LIVE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0FBF6A),
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
  // Frame 2 — Camera Feed
  // ---------------------------------------------------------------------------
  Widget _buildCameraFrame() {
    return Container(
      width: double.infinity,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview or fallback
          if (_isCameraInitialized && _cameraController != null)
            CameraPreview(_cameraController!)
          else if (_isCameraError)
            _buildCameraError()
          else
            _buildCameraLoading(),

          // Overlay: corner brackets (detection frame indicator)
          Positioned.fill(child: _buildDetectionOverlay()),

          // Overlay: label
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam, color: Colors.white, size: 14),
                  SizedBox(width: 5),
                  Text(
                    'CAMERA FEED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Color(0xFF4D8BFF)),
          SizedBox(height: 12),
          Text(
            'Initializing camera…',
            style: TextStyle(color: Color(0xFF5A6275), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.no_photography_rounded,
            color: Color(0xFF5A6275),
            size: 48,
          ),
          const SizedBox(height: 12),
          const Text(
            'Camera unavailable',
            style: TextStyle(color: Color(0xFFE8EAF0), fontSize: 14),
          ),
          const SizedBox(height: 4),
          const Text(
            'Check camera permissions in settings.',
            style: TextStyle(color: Color(0xFF5A6275), fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _isCameraError = false;
                _isCameraInitialized = false;
              });
              _initCamera();
            },
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF4D8BFF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectionOverlay() {
    return CustomPaint(painter: _CornerBracketPainter());
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
          // Total count banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFF2A2F3D), width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.groups_rounded,
                  color: Color(0xFF4D8BFF),
                  size: 22,
                ),
                const SizedBox(width: 10),
                const Text(
                  'TOTAL PASSENGERS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: Color(0xFF5A6275),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E5CF6).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF4D8BFF).withOpacity(0.4),
                    ),
                  ),
                  child: Text(
                    '$_totalPassengers',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF4D8BFF),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _resetAll,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4444).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFFF4444).withOpacity(0.25),
                      ),
                    ),
                    child: const Icon(
                      Icons.restart_alt_rounded,
                      color: Color(0xFFFF6B6B),
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Class table
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                // Table header
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
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

                // Table rows
                ..._classCounts.entries.map(
                  (entry) => _buildClassRow(entry.key, entry.value),
                ),
              ],
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
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFFB8BFCC),
                letterSpacing: 0.2,
              ),
            ),
          ),
          // Decrement
          GestureDetector(
            onTap: () => _decrementClass(className),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.remove, color: accentColor, size: 14),
            ),
          ),
          // Count
          SizedBox(
            width: 36,
            child: Text(
              '$count',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: count > 0 ? accentColor : const Color(0xFF3D4558),
              ),
            ),
          ),
          // Increment
          GestureDetector(
            onTap: () => _incrementClass(className),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.add, color: accentColor, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Custom painter: corner bracket overlay for camera detection frame
// ---------------------------------------------------------------------------
class _CornerBracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF4D8BFF).withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    const margin = 20.0;
    const len = 22.0;

    final corners = [
      // Top-left
      [
        Offset(margin, margin + len),
        Offset(margin, margin),
        Offset(margin + len, margin),
      ],
      // Top-right
      [
        Offset(size.width - margin - len, margin),
        Offset(size.width - margin, margin),
        Offset(size.width - margin, margin + len),
      ],
      // Bottom-left
      [
        Offset(margin, size.height - margin - len),
        Offset(margin, size.height - margin),
        Offset(margin + len, size.height - margin),
      ],
      // Bottom-right
      [
        Offset(size.width - margin - len, size.height - margin),
        Offset(size.width - margin, size.height - margin),
        Offset(size.width - margin, size.height - margin - len),
      ],
    ];

    for (final pts in corners) {
      final path = Path()
        ..moveTo(pts[0].dx, pts[0].dy)
        ..lineTo(pts[1].dx, pts[1].dy)
        ..lineTo(pts[2].dx, pts[2].dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
