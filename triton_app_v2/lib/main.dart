// PROGRAM main.dart
// libraries to import for data handling and math calculations
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:vibration/vibration.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

// ---------------------------------------------------------------------------
// API CONFIG — change this if your backend's IP/port changes
// ---------------------------------------------------------------------------
const String kApiBaseUrl = 'http://192.168.86.245:8000';
// Must match the backend's TRITON_API_KEY env var (or its dev default).
// Only needed for write requests (POST) — the acknowledge endpoints use it.
const String kApiKey = 'dev-key-change-me';

// Pool physical dimensions — MUST stay in sync with backend/pool_zones.py's
// POOL_LENGTH_M / POOL_WIDTH_M constants. Used only for drawing the pool
// sketch at the correct aspect ratio.
const double kPoolLengthM = 25.0;
const double kPoolWidthM = 12.5;

// main call
void main() {
  // audioplayers' AssetSource defaults to looking under an "assets/" prefix
  // regardless of pubspec.yaml — since alarm.wav actually lives at
  // audio/alarm.wav (no assets/ folder), override that default so
  // AssetSource('audio/alarm.wav') resolves to the real path. This is a
  // synchronous, near-instant call — doesn't reintroduce the earlier
  // blocking-before-runApp() lag issue.
  AudioCache.instance = AudioCache(prefix: '');

  // Nothing heavy happens here — runApp() fires immediately so the first
  // frame paints instantly. Data initialization moved to SplashScreen,
  // which runs it AFTER that first frame is already on screen (see its
  // addPostFrameCallback), avoiding any blank/frozen moment at launch.
  runApp(const TritonLifeBandApp());
}

class TritonLifeBandApp extends StatelessWidget {
  const TritonLifeBandApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFFFF1744),
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// SPLASH SCREEN — shown instantly on launch (cheap to build, so there's no
// blank/frozen frame), starts the mock data simulation in the background,
// then hands off to the role selector once it's actually ready.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// TRIDENT BRANDING — a custom-drawn trident (Triton's emblem), used as the
// app's logo throughout, plus a matching ocean-themed background painter.
// Drawn natively in code (not an image asset) so it's crisp at any size,
// perfectly colorable to match the app's theme, and carries zero licensing
// risk since nothing here is a third-party image.
// ---------------------------------------------------------------------------

/// Builds an ornate trident silhouette as a filled Path: a diamond-shaped
/// center blade, two curved outer prongs sweeping outward with a small barb
/// partway up (echoing the reference art's hooked blade shape), a small
/// diamond "gem" where the prongs meet, and a shaft below. Shared by the
/// small TridentIcon widget and the large faint watermark on the ocean
/// background — both just render this same Path at different sizes/opacity.
Path _buildTridentPath(Rect bounds) {
  final w = bounds.width;
  final h = bounds.height;
  final l = bounds.left;
  final t = bounds.top;
  Offset p(double fx, double fy) => Offset(l + fx * w, t + fy * h);

  final path = Path();

  // Center blade — thin, sharp, faceted spike with small angular flares
  // partway down (straight edges only, no curves, for a crystalline look)
  path.moveTo(p(0.5, 0.0).dx, p(0.5, 0.0).dy); // tip
  path.lineTo(p(0.525, 0.14).dx, p(0.525, 0.14).dy);
  path.lineTo(p(0.575, 0.22).dx, p(0.575, 0.22).dy); // right flare spike
  path.lineTo(p(0.515, 0.24).dx, p(0.515, 0.24).dy);
  path.lineTo(p(0.5, 0.38).dx, p(0.5, 0.38).dy); // waist point
  path.lineTo(p(0.485, 0.24).dx, p(0.485, 0.24).dy);
  path.lineTo(p(0.425, 0.22).dx, p(0.425, 0.22).dy); // left flare spike
  path.lineTo(p(0.475, 0.14).dx, p(0.475, 0.14).dy);
  path.close();

  // Left prong — sharp faceted shard: base out to a wide point, up to a
  // needle-sharp tip, back in through a concave notch, then a small inner
  // barb spike back to base. All straight edges.
  final leftBase = p(0.44, 0.34);
  path.moveTo(leftBase.dx, leftBase.dy);
  path.lineTo(p(0.14, 0.30).dx, p(0.14, 0.30).dy); // outward wide point
  path.lineTo(p(0.20, 0.20).dx, p(0.20, 0.20).dy); // up
  path.lineTo(p(0.05, 0.07).dx, p(0.05, 0.07).dy); // sharp tip
  path.lineTo(p(0.22, 0.18).dx, p(0.22, 0.18).dy); // concave notch back in
  path.lineTo(p(0.30, 0.24).dx, p(0.30, 0.24).dy); // inner barb spike
  path.close();

  // Right prong — mirror of left
  final rightBase = p(0.56, 0.34);
  path.moveTo(rightBase.dx, rightBase.dy);
  path.lineTo(p(0.86, 0.30).dx, p(0.86, 0.30).dy);
  path.lineTo(p(0.80, 0.20).dx, p(0.80, 0.20).dy);
  path.lineTo(p(0.95, 0.07).dx, p(0.95, 0.07).dy);
  path.lineTo(p(0.78, 0.18).dx, p(0.78, 0.18).dy);
  path.lineTo(p(0.70, 0.24).dx, p(0.70, 0.24).dy);
  path.close();

  // Small faceted diamond "gem" where the prongs meet
  final gemCenter = p(0.5, 0.42);
  final gemR = w * 0.05;
  path.moveTo(gemCenter.dx, gemCenter.dy - gemR);
  path.lineTo(gemCenter.dx + gemR * 0.7, gemCenter.dy);
  path.lineTo(gemCenter.dx, gemCenter.dy + gemR);
  path.lineTo(gemCenter.dx - gemR * 0.7, gemCenter.dy);
  path.close();

  // Shaft — a slim, slightly tapered blade-like shaft (sharper than a
  // plain rounded rod) with a couple of angular ring bands
  final shaftTopW = w * 0.045;
  final shaftBottomW = w * 0.03;
  final shaftTopY = p(0.5, 0.42).dy;
  final shaftBottomY = p(0.5, 0.98).dy;
  final cx = p(0.5, 0).dx;
  path.moveTo(cx - shaftTopW / 2, shaftTopY);
  path.lineTo(cx + shaftTopW / 2, shaftTopY);
  path.lineTo(cx + shaftBottomW / 2, shaftBottomY);
  path.lineTo(cx - shaftBottomW / 2, shaftBottomY);
  path.close();

  return path;
}

/// Adds two thin angular ring-band rectangles across the shaft for a
/// segmented/wrapped-handle detail — drawn separately since they're a
/// different (darker) fill than the main trident color.
List<Rect> _tridentShaftBands(Rect bounds) {
  final w = bounds.width;
  final h = bounds.height;
  final l = bounds.left;
  final t = bounds.top;
  final bandWidth = w * 0.09;
  final left = l + w * 0.5 - bandWidth / 2;
  return [
    Rect.fromLTWH(left, t + h * 0.58, bandWidth, h * 0.018),
    Rect.fromLTWH(left, t + h * 0.76, bandWidth, h * 0.018),
  ];
}

class TridentIcon extends StatelessWidget {
  final double size;
  final Color color;

  const TridentIcon({
    super.key,
    this.size = 40,
    this.color = const Color(0xFF00E5FF),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _TridentPainter(color: color)),
    );
  }
}

class _TridentPainter extends CustomPainter {
  final Color color;
  _TridentPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);
    final path = _buildTridentPath(bounds);

    // Wide, soft outer glow
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.18),
    );
    // Tighter, brighter inner glow for a sharper "cool" icy core
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.06),
    );

    // Icy gradient fill — white-hot core fading to the theme color at the
    // edges, for a cooler, sharper-looking blade than a flat single color
    final gradientPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, color],
        stops: const [0.0, 0.6],
      ).createShader(bounds);
    canvas.drawPath(path, gradientPaint);

    // Thin bright white outline for crisp edge definition
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.01,
    );

    // Shaft wrap bands, darker than the main color
    final bandPaint = Paint()..color = Colors.black.withValues(alpha: 0.4);
    for (final band in _tridentShaftBands(bounds)) {
      canvas.drawRect(band, bandPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TridentPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Ocean-themed background: a dark navy-to-black gradient, a few faint wave
/// lines, and one large, very faint trident watermark — used behind the
/// role selection screen's content.
class OceanBackground extends StatelessWidget {
  const OceanBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          // The actual photo
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/ocean_bg.jpg'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Dark tint on top — dims the photo so foreground text/buttons
          // stay readable. Adjust the opacity (0.0-1.0) to taste: higher
          // = darker/less bright.
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.55)),
          ),
        ],
      ),
    );
  }
}

class _OceanBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Large faint, glowing trident watermark, centered
    final tridentSize = size.width * 0.7;
    final tridentBounds = Rect.fromLTWH(
      (size.width - tridentSize) / 2,
      size.height * 0.18,
      tridentSize,
      tridentSize,
    );
    final tridentPath = _buildTridentPath(tridentBounds);

    canvas.drawPath(
      tridentPath,
      Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.12)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, tridentSize * 0.05),
    );
    canvas.drawPath(
      tridentPath,
      Paint()..color = const Color(0xFF00E5FF).withValues(alpha: 0.07),
    );

    // A few faint wave curves near the bottom
    final wavePaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.08)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 3; i++) {
      final baseY = size.height * (0.75 + i * 0.07);
      final path = Path()..moveTo(0, baseY);
      for (double x = 0; x <= size.width; x += size.width / 8) {
        path.quadraticBezierTo(
          x + size.width / 16,
          baseY + (i.isEven ? 10 : -10),
          x + size.width / 8,
          baseY,
        );
      }
      canvas.drawPath(path, wavePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OceanBackgroundPainter oldDelegate) => false;
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Runs AFTER this screen's first frame has already been painted, so the
    // spinner/logo below appears instantly with zero perceived lag — the
    // (fast, but non-zero) data setup work happens only once something is
    // already visible on screen.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _initializeAndProceed(),
    );
  }

  Future<void> _initializeAndProceed() async {
    await NotificationService.instance.init();
    MockDataService.instance.start();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RoleSelectScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF121212),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TridentIcon(size: 64, color: Color(0xFF00E5FF)),
            SizedBox(height: 20),
            Text(
              "TRITON LIFEBAND",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(color: Color(0xFF00E5FF)),
            SizedBox(height: 16),
            Text(
              "Loading...",
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// DATA MODELS
// ---------------------------------------------------------------------------

/// App-wide adjustable settings — thresholds that were previously hardcoded
/// constants. Kept in-memory only (resets on app restart) for now; would
/// need shared_preferences or a backend-stored config to persist across
/// launches or sync across devices.
class AppSettings extends ChangeNotifier {
  AppSettings._internal();
  static final AppSettings instance = AppSettings._internal();

  double redUrgencyThreshold = 66.0;
  double yellowUrgencyThreshold = 33.0;
  int offlineThresholdSeconds = 60;
  double lowBatteryThreshold = 20.0;

  void update({
    double? red,
    double? yellow,
    int? offlineSeconds,
    double? lowBattery,
  }) {
    if (red != null) redUrgencyThreshold = red;
    if (yellow != null) yellowUrgencyThreshold = yellow;
    if (offlineSeconds != null) offlineThresholdSeconds = offlineSeconds;
    if (lowBattery != null) lowBatteryThreshold = lowBattery;
    notifyListeners();
  }
}

/// Single source of truth for red/yellow/blue bucketing, used by both the
/// Pool Status screen (Victim.bucket) and the Dashboard screen — keeping
/// this in one place means they can never disagree with each other.
String bucketForScore(double urgencyScore) {
  if (urgencyScore >= AppSettings.instance.redUrgencyThreshold) return "red";
  if (urgencyScore >= AppSettings.instance.yellowUrgencyThreshold) {
    return "yellow";
  }
  return "blue";
}

Color colorForBucket(String bucket) {
  switch (bucket) {
    case "red":
      return const Color(0xFFFF1744);
    case "yellow":
      return const Color(0xFFFFEA00);
    case "blue":
      return const Color(0xFF00E5FF);
    default:
      return Colors.white38;
  }
}

class Victim {
  final int id;
  final String name;
  final String deviceId;
  final double? ageYears;
  final Telemetry? latestTelemetry;
  final bool acknowledgedOnBackend; // only meaningful for real (non-mock) data

  Victim({
    required this.id,
    required this.name,
    required this.deviceId,
    this.ageYears,
    this.latestTelemetry,
    this.acknowledgedOnBackend = false,
  });

  factory Victim.fromJson(Map<String, dynamic> json) {
    return Victim(
      id: json['id'],
      name: json['name'],
      deviceId: json['device_id'],
      ageYears: (json['age_years'] as num?)?.toDouble(),
      latestTelemetry: json['latest_telemetry'] != null
          ? Telemetry.fromJson(json['latest_telemetry'])
          : null,
      acknowledgedOnBackend: json['acknowledged'] ?? false,
    );
  }

  /// Unifies backend-persisted acknowledgment (real data — synced across
  /// every device) with the local-only fallback (mock data has no backend
  /// record to persist to).
  bool get isAcknowledged =>
      acknowledgedOnBackend || AcknowledgeService.instance.isAcknowledged(id);

  /// Bucketizes this victim into red/yellow/blue based on the backend's
  /// urgency_score. See bucketForScore() for the shared thresholds.
  String get bucket {
    final t = latestTelemetry;
    if (t == null) return "unknown";
    return bucketForScore(t.urgencyScore);
  }

  Color get bucketColor =>
      bucket == "unknown" ? Colors.white38 : colorForBucket(bucket);

  String get bucketLabel {
    switch (bucket) {
      case "red":
        return "CRITICAL";
      case "yellow":
        return "WARNING";
      case "blue":
        return "STABLE";
      default:
        return "NO DATA";
    }
  }
}

class Telemetry {
  final int id;
  final int victimId;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final double bpm;
  final int piezoDepth;

  final double depthM;
  final double? riseRateMPerHr;
  final double bpmCritical;
  final double? hoursToCriticalDepth;
  final double urgencyScore;
  final bool coveredUrgencyStop;
  final double? distKm;
  final double? ageYears;
  final double bpmNormLow;
  final double bpmNormHigh;
  final double ageVulnerability;
  final double? batteryPct;
  final double? batteryDrainPctPerMin;

  final int? zoneNumber;
  final String poolZone;
  final double? poolXNorm;
  final double? poolYNorm;

  Telemetry({
    required this.id,
    required this.victimId,
    required this.timestamp,
    this.latitude,
    this.longitude,
    required this.bpm,
    required this.piezoDepth,
    required this.depthM,
    this.riseRateMPerHr,
    required this.bpmCritical,
    this.hoursToCriticalDepth,
    required this.urgencyScore,
    required this.coveredUrgencyStop,
    this.distKm,
    this.ageYears,
    required this.bpmNormLow,
    required this.bpmNormHigh,
    required this.ageVulnerability,
    this.batteryPct,
    this.batteryDrainPctPerMin,
    this.zoneNumber,
    required this.poolZone,
    this.poolXNorm,
    this.poolYNorm,
  });

  factory Telemetry.fromJson(Map<String, dynamic> json) {
    return Telemetry(
      id: json['id'],
      victimId: json['victim_id'],
      timestamp: DateTime.parse(json['timestamp']),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      bpm: (json['bpm'] as num).toDouble(),
      piezoDepth: json['piezo_depth'],
      depthM: (json['depth_m'] as num).toDouble(),
      riseRateMPerHr: (json['rise_rate_m_per_hr'] as num?)?.toDouble(),
      bpmCritical: (json['bpm_critical'] as num).toDouble(),
      hoursToCriticalDepth: (json['hours_to_critical_depth'] as num?)
          ?.toDouble(),
      urgencyScore: (json['urgency_score'] as num).toDouble(),
      coveredUrgencyStop: json['covered_urgency_stop'] ?? false,
      distKm: (json['dist_km'] as num?)?.toDouble(),
      ageYears: (json['age_years'] as num?)?.toDouble(),
      bpmNormLow: (json['bpm_norm_low'] as num).toDouble(),
      bpmNormHigh: (json['bpm_norm_high'] as num).toDouble(),
      ageVulnerability: (json['age_vulnerability'] as num).toDouble(),
      batteryPct: (json['battery_pct'] as num?)?.toDouble(),
      batteryDrainPctPerMin: (json['battery_drain_pct_per_min'] as num?)
          ?.toDouble(),
      zoneNumber: json['zone_number'],
      poolZone: json['pool_zone'] ?? 'Unknown Zone',
      poolXNorm: (json['pool_x_norm'] as num?)?.toDouble(),
      poolYNorm: (json['pool_y_norm'] as num?)?.toDouble(),
    );
  }
}

// ---------------------------------------------------------------------------
// ROLE SELECT SCREEN — new app home
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// SETTINGS SCREEN — adjustable thresholds, previously hardcoded constants.
// In-memory only for now (resets on app restart) — would need
// shared_preferences to persist across launches, or backend storage to
// sync the same settings across multiple devices.
// ---------------------------------------------------------------------------

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double _red;
  late double _yellow;
  late double _offlineSeconds;
  late double _lowBattery;

  @override
  void initState() {
    super.initState();
    _red = AppSettings.instance.redUrgencyThreshold;
    _yellow = AppSettings.instance.yellowUrgencyThreshold;
    _offlineSeconds = AppSettings.instance.offlineThresholdSeconds.toDouble();
    _lowBattery = AppSettings.instance.lowBatteryThreshold;
  }

  void _apply() {
    AppSettings.instance.update(
      red: _red,
      yellow: _yellow,
      offlineSeconds: _offlineSeconds.round(),
      lowBattery: _lowBattery,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("SETTINGS"),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            "These settings are in-memory only right now — they reset when "
            "the app restarts. Adjust here to tune against real test data.",
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 24),
          _buildSlider(
            label: "Critical (red) urgency threshold",
            value: _red,
            min: _yellow + 1,
            max: 100,
            display: _red.toStringAsFixed(0),
            onChanged: (v) => setState(() {
              _red = v;
              _apply();
            }),
          ),
          _buildSlider(
            label: "Warning (yellow) urgency threshold",
            value: _yellow,
            min: 0,
            max: _red - 1,
            display: _yellow.toStringAsFixed(0),
            onChanged: (v) => setState(() {
              _yellow = v;
              _apply();
            }),
          ),
          _buildSlider(
            label: "Offline threshold (seconds of silence)",
            value: _offlineSeconds,
            min: 10,
            max: 300,
            display: "${_offlineSeconds.round()}s",
            onChanged: (v) => setState(() {
              _offlineSeconds = v;
              _apply();
            }),
          ),
          _buildSlider(
            label: "Low battery threshold",
            value: _lowBattery,
            min: 5,
            max: 50,
            display: "${_lowBattery.toStringAsFixed(0)}%",
            onChanged: (v) => setState(() {
              _lowBattery = v;
              _apply();
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
              Text(
                display,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00E5FF),
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: const Color(0xFF00E5FF),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            TridentIcon(size: 22, color: Color(0xFF00E5FF)),
            SizedBox(width: 8),
            Text(
              "TRITON LIFEBAND",
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: Stack(
        children: [
          const OceanBackground(),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "SELECT YOUR ROLE",
                  style: TextStyle(
                    fontSize: 14,
                    letterSpacing: 1.5,
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(height: 24),
                _RoleButton(
                  icon: Icons.pool,
                  label: "LIFEGUARD",
                  subtitle: "Pool monitoring & zone lookup",
                  color: const Color(0xFF00E5FF),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const VictimsListScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _RoleButton(
                  icon: Icons.emergency,
                  label: "FIRST RESPONDER",
                  subtitle: "Flood tracking & real-time map",
                  color: const Color(0xFFFF1744),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FloodVictimsListScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _RoleButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 2),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black38),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// MOCK DATA SERVICE — a single, app-wide simulation that starts once when
// the app launches and keeps running continuously in the background,
// regardless of which screen is open. Every screen (Pool Status, Flood
// Status, an individual band's Dashboard) reads from this SAME source, so
// they always agree on a given band's current state instead of each screen
// independently randomizing its own disconnected data.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// OFFLINE DETECTION — a band that's stopped reporting is a real risk (no
// data isn't the same as "safe"), so this is treated as its own category,
// checked purely against wall-clock time rather than waiting for new data.
// ---------------------------------------------------------------------------

bool isVictimOffline(Victim v) {
  final t = v.latestTelemetry;
  if (t == null) {
    return false; // never reported at all — treated separately, not "offline"
  }
  return DateTime.now().difference(t.timestamp).inSeconds >
      AppSettings.instance.offlineThresholdSeconds;
}

/// A device whose battery is getting low is a real risk even if the
/// victim's own vitals look fine right now — a dead device soon becomes
/// an offline device, with no warning.
bool isVictimLowBattery(Victim v) {
  final pct = v.latestTelemetry?.batteryPct;
  if (pct == null) return false;
  return pct < AppSettings.instance.lowBatteryThreshold;
}

String formatLastSeen(DateTime timestamp) {
  final seconds = DateTime.now().difference(timestamp).inSeconds;
  if (seconds < 60) return "${seconds}s ago";
  final minutes = seconds ~/ 60;
  if (minutes < 60) return "${minutes}m ago";
  final hours = minutes ~/ 60;
  return "${hours}h ago";
}

// ---------------------------------------------------------------------------
// DIRECTIONS — hands off to the phone's own Maps app (Apple Maps on iOS,
// Google Maps as a fallback/on Android) for real turn-by-turn navigation.
// Deliberately NOT building our own routing/navigation — Maps already does
// real road-based routing using the phone's live GPS location automatically
// (no location permission needed in THIS app, since Maps handles that
// itself once it opens).
// ---------------------------------------------------------------------------

Future<void> openDirections(
  BuildContext context,
  double lat,
  double lng,
) async {
  // Both URLs default the starting point to the phone's current location
  // automatically when no source is specified — Maps handles getting that
  // live, we don't need to request location permission in this app at all.
  final appleMapsUrl = Uri.parse(
    'https://maps.apple.com/?daddr=$lat,$lng&dirflg=d',
  );
  final googleMapsUrl = Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
  );

  try {
    if (await canLaunchUrl(appleMapsUrl)) {
      await launchUrl(appleMapsUrl, mode: LaunchMode.externalApplication);
      return;
    }
    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No maps app available to open directions."),
        ),
      );
    }
  } catch (e) {
    debugPrint("Failed to open directions: $e");
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Couldn't open directions: $e")));
    }
  }
}

// ---------------------------------------------------------------------------
// ACKNOWLEDGE SERVICE — lets a lifeguard/responder mark "I'm already
// handling this one" so a second person glancing at the same list doesn't
// duplicate effort. This is intentionally per-device (in-memory, not synced
// to the backend) for now — it solves single-phone coordination immediately;
// true multi-device sync would need this persisted server-side later.
// ---------------------------------------------------------------------------

class AcknowledgeService extends ChangeNotifier {
  AcknowledgeService._internal();
  static final AcknowledgeService instance = AcknowledgeService._internal();

  final Set<int> _acknowledgedIds = {};

  bool isAcknowledged(int victimId) => _acknowledgedIds.contains(victimId);

  /// [syncToBackend] should be true for real (non-mock) victims — this
  /// persists the acknowledgment server-side so every device sees the same
  /// state, not just the phone that tapped it. Mock victims have no real
  /// backend record, so they stay local-only regardless.
  Future<void> acknowledge(int victimId, {bool syncToBackend = false}) async {
    _acknowledgedIds.add(victimId);
    notifyListeners();
    if (syncToBackend) {
      try {
        await http.post(
          Uri.parse('$kApiBaseUrl/victims/$victimId/acknowledge'),
          headers: {'X-API-Key': kApiKey},
        );
      } catch (e) {
        debugPrint("Failed to sync acknowledgment to backend: $e");
      }
    }
  }

  /// Called when a victim exits red/critical — clears any stale
  /// acknowledgment so a FUTURE critical episode starts fresh/unacknowledged.
  Future<void> clear(int victimId, {bool syncToBackend = false}) async {
    if (_acknowledgedIds.remove(victimId)) notifyListeners();
    if (syncToBackend) {
      try {
        await http.post(
          Uri.parse('$kApiBaseUrl/victims/$victimId/unacknowledge'),
          headers: {'X-API-Key': kApiKey},
        );
      } catch (e) {
        debugPrint("Failed to sync unacknowledgment to backend: $e");
      }
    }
  }
}

// ---------------------------------------------------------------------------
// NOTIFICATION SERVICE — local notifications only. These reliably fire
// while the app is running (foreground, or backgrounded briefly) but do
// NOT work once the app has been fully force-quit — that requires real push
// infrastructure (Apple APNs / Firebase), which itself needs a paid Apple
// Developer Program membership. This is a real gap worth knowing about,
// not something this local-notifications approach can fully close.
// ---------------------------------------------------------------------------

class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const settings = InitializationSettings(
      iOS: iosSettings,
      android: androidSettings,
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<void> showAlert({required String title, required String body}) async {
    if (!_initialized) await init();
    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      ),
      android: AndroidNotificationDetails(
        'triton_critical_channel',
        'Critical Alerts',
        importance: Importance.max,
        priority: Priority.high,
      ),
    );
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000, // unique-ish id
      title,
      body,
      details,
    );
  }
}

class MockDataService extends ChangeNotifier {
  MockDataService._internal();
  static final MockDataService instance = MockDataService._internal();

  List<Victim> victims = [];
  Timer? _timer;

  // Rolling history per victim (most recent last), capped at 20 entries —
  // enough for a simple trend chart without growing unbounded in memory.
  final Map<int, List<Telemetry>> _history = {};
  static const int _maxHistoryLength = 20;

  /// Starts the simulation if it isn't already running. Safe to call from
  /// multiple screens' initState — subsequent calls are a no-op.
  void start() {
    if (_timer != null) return; // already running
    victims = createMockVictims();
    _tick(); // populate immediately rather than waiting 3s for the first tick
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
  }

  void _tick() {
    victims = regenerateMockVictims(victims);
    for (final v in victims) {
      final t = v.latestTelemetry;
      if (t == null) continue;
      final list = _history.putIfAbsent(v.id, () => []);
      list.add(t);
      if (list.length > _maxHistoryLength) list.removeAt(0);
    }
    notifyListeners(); // every screen listening reacts to this SAME instant,
    // instead of each screen polling on its own separate
    // schedule and drifting out of sync with each other
  }

  Victim? getById(int id) {
    try {
      return victims.firstWhere((v) => v.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Recent readings for one victim, oldest first — used for the
  /// Dashboard's historical trend chart in mock mode.
  List<Telemetry> getHistory(int id) => List.unmodifiable(_history[id] ?? []);
}

// ---------------------------------------------------------------------------
// SHARED MOCK DATA GENERATION — used by both Pool Status and Flood Status so
// their simulated fluctuations follow identical logic and can never drift
// apart from each other.
// ---------------------------------------------------------------------------

/// Creates 50 persistent mock identities (LB001-LB050) with stable names/ages.
/// A real-world-ish scatter of lat/lng is included so Flood Status has
/// something plausible to plot on the map (roughly Austin, TX area).
List<Victim> createMockVictims() {
  final rand = Random();
  return List.generate(50, (i) {
    final n = i + 1;
    return Victim(
      id: n,
      name: "LB${n.toString().padLeft(3, '0')}",
      deviceId: "LB${n.toString().padLeft(3, '0')}",
      ageYears: (6 + rand.nextInt(70)).toDouble(),
      latestTelemetry: null,
    );
  });
}

/// Regenerates fluctuating vitals for every mock victim in the given list,
/// mostly normal readings with some rolled into elevated/critical ranges.
List<Victim> regenerateMockVictims(List<Victim> victims) {
  final rand = Random();
  const sampleZones = [
    "Zone 1, Shallow Pool, Left",
    "Zone 2, Shallow Pool, Right",
    "Zone 3, Mid Pool, Left",
    "Zone 4, Mid Pool, Right",
    "Zone 5, Deep Pool, Left",
    "Zone 6, Deep Pool, Right",
  ];
  // Roughly Austin, TX — scattered over a real few-km area, for Flood
  // Status's map to have plausible spread rather than everyone stacked
  // on one point.
  const baseLat = 30.2672;
  const baseLng = -97.7431;

  return victims.map((v) {
    final age = v.ageYears ?? 30.0;
    final bpmCritical = 208.0 - (0.7 * age);
    final bpmNormLow = 50.0;
    final bpmNormHigh = 0.85 * bpmCritical;
    final ageVulnerability = (age < 12 || age > 65)
        ? 1.0
        : ((age < 18 || age > 50) ? 0.6 : 0.3);

    double bpm;
    int piezoDepth;
    double urgencyScore;

    final roll = rand.nextDouble();
    if (roll < 0.10) {
      bpm = rand.nextBool()
          ? (145 + rand.nextInt(25)).toDouble()
          : (30 + rand.nextInt(10)).toDouble();
      piezoDepth = 3600 + rand.nextInt(496);
      urgencyScore = 66 + rand.nextDouble() * 34; // red
    } else if (roll < 0.25) {
      bpm = (100 + rand.nextInt(40)).toDouble();
      piezoDepth = 2300 + rand.nextInt(1100);
      urgencyScore = 33 + rand.nextDouble() * 33; // yellow
    } else {
      bpm = (65 + rand.nextInt(30)).toDouble();
      piezoDepth = 700 + rand.nextInt(1300);
      urgencyScore = rand.nextDouble() * 33; // blue
    }

    final depthM = (piezoDepth / 4095.0) * 3.0;
    final batteryPct = 15 + rand.nextInt(85);

    // Scatter within roughly +/- 0.03 degrees (~3km) of the base point —
    // plausible for a flood-response area, not a tiny pool.
    final lat = baseLat + (rand.nextDouble() - 0.5) * 0.06;
    final lng = baseLng + (rand.nextDouble() - 0.5) * 0.06;

    final telemetry = Telemetry(
      id: v.id,
      victimId: v.id,
      timestamp: DateTime.now(),
      latitude: lat,
      longitude: lng,
      bpm: bpm,
      piezoDepth: piezoDepth,
      depthM: depthM,
      riseRateMPerHr: null,
      bpmCritical: bpmCritical,
      hoursToCriticalDepth: null,
      urgencyScore: double.parse(urgencyScore.toStringAsFixed(1)),
      coveredUrgencyStop: false,
      distKm: null,
      ageYears: age,
      bpmNormLow: bpmNormLow,
      bpmNormHigh: bpmNormHigh,
      ageVulnerability: ageVulnerability,
      batteryPct: batteryPct.toDouble(),
      batteryDrainPctPerMin: 0.05 + rand.nextDouble() * 0.1,
      zoneNumber: null,
      poolZone: sampleZones[rand.nextInt(sampleZones.length)],
      poolXNorm: rand.nextDouble(),
      poolYNorm: rand.nextDouble(),
    );

    return Victim(
      id: v.id,
      name: v.name,
      deviceId: v.deviceId,
      ageYears: v.ageYears,
      latestTelemetry: telemetry,
    );
  }).toList();
}

/// Shared bordered alert section — used identically by both Pool Status
/// (red/yellow) and Flood Status (red/yellow), just with a different
/// onTap destination per screen. Returns an empty widget if there's
/// nothing to show.
Widget buildAlertSection({
  required BuildContext context,
  required String title,
  required Color color,
  required List<Victim> victims,
  required void Function(BuildContext context, Victim victim) onTapVictim,
  bool showAcknowledge = false,
  bool showLastSeen = false,
  bool showBattery = false,
  bool syncAcknowledgeToBackend = false,
}) {
  if (victims.isEmpty) return const SizedBox.shrink();

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color, width: 2),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: color),
            const SizedBox(width: 8),
            Text(
              "$title (${victims.length})",
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: victims.map((v) {
            final score = v.latestTelemetry?.urgencyScore;
            final acknowledged = showAcknowledge && v.isAcknowledged;
            String label;
            if (showLastSeen && v.latestTelemetry != null) {
              label =
                  "${v.name} · ${formatLastSeen(v.latestTelemetry!.timestamp)}";
            } else if (showBattery && v.latestTelemetry?.batteryPct != null) {
              label =
                  "${v.name} · ${v.latestTelemetry!.batteryPct!.toStringAsFixed(0)}%";
            } else {
              label = score != null
                  ? "${v.name} · ${score.toStringAsFixed(0)}"
                  : v.name;
            }
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onTapVictim(context, v),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: acknowledged
                      ? Colors.black.withValues(alpha: 0.5)
                      : Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: acknowledged
                      ? []
                      : [
                          BoxShadow(
                            color: color.withValues(alpha: 0.7),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: acknowledged ? Colors.white54 : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        decoration: acknowledged
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    if (showAcknowledge) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => AcknowledgeService.instance.acknowledge(
                          v.id,
                          syncToBackend: syncAcknowledgeToBackend,
                        ),
                        child: Icon(
                          acknowledged
                              ? Icons.check_circle
                              : Icons.check_circle_outline,
                          size: 18,
                          color: acknowledged
                              ? Colors.greenAccent
                              : Colors.white54,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// FLOOD VICTIMS LIST SCREEN — First Responder / flood home
// ---------------------------------------------------------------------------

class FloodVictimsListScreen extends StatefulWidget {
  const FloodVictimsListScreen({super.key});

  @override
  State<FloodVictimsListScreen> createState() => _FloodVictimsListScreenState();
}

class _FloodVictimsListScreenState extends State<FloodVictimsListScreen> {
  Timer? _pollingTimer;
  Timer? _uiRefreshTimer;
  List<Victim> _victims = [];
  bool _loading = true;
  String? _errorMessage;

  bool _useMockData = true;
  bool _showMap = false;

  // Tracks which victims were in the CRITICAL DISTRESS box, and which were
  // offline, last time we checked — so we can detect NEW entries into
  // either category and alert once, rather than re-alerting every tick.
  Set<int> _previousRedIds = {};
  Set<int> _previousOfflineIds = {};
  Set<int> _previousLowBatteryIds = {};
  final AudioPlayer _alertPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    MockDataService.instance.start(); // no-op if already running elsewhere
    MockDataService.instance.addListener(_onMockDataChanged);
    _pullMockData();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_useMockData) _fetchVictims();
    });
    // Offline status depends purely on wall-clock time, not on new data
    // arriving — this forces a re-render periodically so "last seen Xs
    // ago" and the offline threshold stay accurate even if nothing new
    // has come in.
    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
      _checkForNewCritical();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _uiRefreshTimer?.cancel();
    MockDataService.instance.removeListener(_onMockDataChanged);
    _alertPlayer.dispose();
    super.dispose();
  }

  void _onMockDataChanged() {
    if (_useMockData) _pullMockData();
  }

  Future<void> _fetchVictims() async {
    try {
      final response = await http
          .get(Uri.parse('$kApiBaseUrl/victims'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _victims = data.map((v) => Victim.fromJson(v)).toList();
          _loading = false;
          _errorMessage = null;
        });
        _checkForNewCritical();
      } else {
        setState(() {
          _errorMessage = 'Server returned ${response.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Cannot reach backend: $e';
        _loading = false;
      });
    }
  }

  /// Reads the current state of the app-wide simulation — does NOT generate
  /// new data itself, since MockDataService.instance already keeps ticking
  /// on its own in the background regardless of this screen's lifecycle.
  void _pullMockData() {
    setState(() {
      _victims = MockDataService.instance.victims;
      _loading = false;
      _errorMessage = null;
    });
    _checkForNewCritical();
  }

  /// Compares this update's CRITICAL DISTRESS, OFFLINE, and LOW BATTERY
  /// contents against last time — if anyone NEW shows up in any of them,
  /// fires a vibration + one play-through of the alarm sound + a local
  /// notification. Also auto-clears acknowledgment for anyone who's exited
  /// red, so a FUTURE critical episode for them starts fresh/unacknowledged.
  void _checkForNewCritical() {
    final currentRedIds = _victims
        .where((v) => v.bucket == "red")
        .map((v) => v.id)
        .toSet();
    final currentOfflineIds = _victims
        .where(isVictimOffline)
        .map((v) => v.id)
        .toSet();
    final currentLowBatteryIds = _victims
        .where(isVictimLowBattery)
        .map((v) => v.id)
        .toSet();

    final newlyCritical = currentRedIds.difference(_previousRedIds);
    final newlyOffline = currentOfflineIds.difference(_previousOfflineIds);
    final newlyLowBattery = currentLowBatteryIds.difference(
      _previousLowBatteryIds,
    );
    final exitedRed = _previousRedIds.difference(currentRedIds);

    for (final id in exitedRed) {
      AcknowledgeService.instance.clear(id, syncToBackend: !_useMockData);
    }

    if (newlyCritical.isNotEmpty) {
      final names = _victims
          .where((v) => newlyCritical.contains(v.id))
          .map((v) => v.name)
          .join(", ");
      _triggerAlert(
        title: "Critical Distress",
        body: "$names now in critical distress",
      );
    }
    if (newlyOffline.isNotEmpty) {
      final names = _victims
          .where((v) => newlyOffline.contains(v.id))
          .map((v) => v.name)
          .join(", ");
      _triggerAlert(title: "Device Offline", body: "$names stopped reporting");
    }
    if (newlyLowBattery.isNotEmpty) {
      final names = _victims
          .where((v) => newlyLowBattery.contains(v.id))
          .map((v) => v.name)
          .join(", ");
      _triggerAlert(title: "Low Battery", body: "$names battery running low");
    }

    _previousRedIds = currentRedIds;
    _previousOfflineIds = currentOfflineIds;
    _previousLowBatteryIds = currentLowBatteryIds;
  }

  Future<void> _triggerAlert({
    required String title,
    required String body,
  }) async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(
        pattern: [0, 500, 200, 500, 200, 800],
        intensities: [0, 255, 0, 255, 0, 255],
      );
    }
    await _alertPlayer.stop();
    await _alertPlayer.setReleaseMode(
      ReleaseMode.release,
    ); // play once, don't loop
    await _alertPlayer.play(AssetSource('audio/alarm.wav'));
    // Local notification — fires while the app is running (foreground or
    // briefly backgrounded). Will NOT fire if the app has been fully
    // force-quit; that requires real push infrastructure (APNs/FCM).
    await NotificationService.instance.showAlert(title: title, body: body);
  }

  void _toggleMockData(bool value) {
    setState(() => _useMockData = value);
    if (value) {
      _pullMockData();
    } else {
      _fetchVictims();
    }
  }

  void _openVictim(BuildContext context, Victim victim) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DashboardScreen(
          victimId: victim.id,
          victimName: victim.name,
          isFloodMode: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "FLOOD STATUS",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1A1A1A),
        actions: [
          Row(
            children: [
              const Text("Mock Data", style: TextStyle(fontSize: 12)),
              Switch(
                value: _useMockData,
                onChanged: _toggleMockData,
                activeThumbColor: const Color(0xFF00E5FF),
              ),
            ],
          ),
          IconButton(
            icon: Icon(_showMap ? Icons.list : Icons.map),
            tooltip: _showMap ? "List view" : "Map view (all victims)",
            onPressed: () => setState(() => _showMap = !_showMap),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _useMockData ? _pullMockData : _fetchVictims,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: _showMap ? _buildMapView() : _buildBody(),
    );
  }

  /// Shows every victim with a valid GPS fix as a colored marker on one
  /// map — situational awareness at a glance, instead of working through
  /// the list one person at a time.
  Widget _buildMapView() {
    final withFix = _victims
        .where(
          (v) =>
              v.latestTelemetry?.latitude != null &&
              v.latestTelemetry?.longitude != null,
        )
        .toList();

    if (withFix.isEmpty) {
      return const Center(
        child: Text(
          "No victims with a GPS fix right now.",
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    final center = latlong.LatLng(
      withFix.first.latestTelemetry!.latitude!,
      withFix.first.latestTelemetry!.longitude!,
    );

    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: 15),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.ananth.tritonApp',
        ),
        MarkerLayer(
          markers: withFix.map((v) {
            final t = v.latestTelemetry!;
            return Marker(
              point: latlong.LatLng(t.latitude!, t.longitude!),
              width: 60,
              height: 60,
              child: GestureDetector(
                onTap: () => _showVictimMapActions(v),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_pin, color: v.bucketColor, size: 36),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        v.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors', onTap: () {}),
          ],
        ),
      ],
    );
  }

  /// Bottom sheet shown when tapping a marker on the all-victims map —
  /// lets a responder either open full details or jump straight to
  /// turn-by-turn directions without navigating through the Dashboard first.
  void _showVictimMapActions(Victim v) {
    final t = v.latestTelemetry;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.person_pin_circle, color: v.bucketColor),
              title: Text(
                v.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(v.bucketLabel),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.white70),
              title: const Text("View Details"),
              onTap: () {
                Navigator.pop(ctx);
                _openVictim(context, v);
              },
            ),
            if (t?.latitude != null && t?.longitude != null)
              ListTile(
                leading: const Icon(Icons.directions, color: Color(0xFFFF1744)),
                title: const Text("Get Directions"),
                onTap: () {
                  Navigator.pop(ctx);
                  openDirections(context, t!.latitude!, t.longitude!);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, color: Colors.white38, size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchVictims,
                child: const Text("Retry"),
              ),
            ],
          ),
        ),
      );
    }

    final offlineVictims = _victims.where(isVictimOffline).toList()
      ..sort(
        (a, b) => a.latestTelemetry!.timestamp.compareTo(
          b.latestTelemetry!.timestamp,
        ),
      );
    final lowBatteryVictims =
        _victims
            .where((v) => isVictimLowBattery(v) && !isVictimOffline(v))
            .toList()
          ..sort(
            (a, b) => (a.latestTelemetry?.batteryPct ?? 100).compareTo(
              b.latestTelemetry?.batteryPct ?? 100,
            ),
          );
    final redVictims =
        _victims.where((v) => v.bucket == "red" && !isVictimOffline(v)).toList()
          ..sort(
            (a, b) => (b.latestTelemetry?.urgencyScore ?? 0).compareTo(
              a.latestTelemetry?.urgencyScore ?? 0,
            ),
          );
    final yellowVictims =
        _victims
            .where((v) => v.bucket == "yellow" && !isVictimOffline(v))
            .toList()
          ..sort(
            (a, b) => (b.latestTelemetry?.urgencyScore ?? 0).compareTo(
              a.latestTelemetry?.urgencyScore ?? 0,
            ),
          );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.sensors, color: Color(0xFF00E5FF), size: 22),
                const SizedBox(width: 10),
                Text(
                  "ACTIVE DEVICES: ${_victims.length}",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              buildAlertSection(
                context: context,
                title: "OFFLINE",
                color: Colors.grey,
                victims: offlineVictims,
                onTapVictim: _openVictim,
                showLastSeen: true,
              ),
              if (offlineVictims.isNotEmpty &&
                  (redVictims.isNotEmpty ||
                      yellowVictims.isNotEmpty ||
                      lowBatteryVictims.isNotEmpty))
                const SizedBox(height: 12),
              buildAlertSection(
                context: context,
                title: "CRITICAL DISTRESS",
                color: const Color(0xFFFF1744),
                victims: redVictims,
                onTapVictim: _openVictim,
                showAcknowledge: true,
                syncAcknowledgeToBackend: !_useMockData,
              ),
              if (redVictims.isNotEmpty && yellowVictims.isNotEmpty)
                const SizedBox(height: 12),
              buildAlertSection(
                context: context,
                title: "WARNING",
                color: const Color(0xFFFFEA00),
                victims: yellowVictims,
                onTapVictim: _openVictim,
              ),
              if (yellowVictims.isNotEmpty && lowBatteryVictims.isNotEmpty)
                const SizedBox(height: 12),
              buildAlertSection(
                context: context,
                title: "LOW BATTERY",
                color: Colors.orange,
                victims: lowBatteryVictims,
                onTapVictim: _openVictim,
                showBattery: true,
              ),
              if (redVictims.isEmpty &&
                  yellowVictims.isEmpty &&
                  offlineVictims.isEmpty &&
                  lowBatteryVictims.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(
                    child: Text(
                      "No flood victims currently at risk.\nNo red or yellow alerts right now.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// VICTIMS LIST SCREEN (grid of cards) — Lifeguard / pool home
// ---------------------------------------------------------------------------

class VictimsListScreen extends StatefulWidget {
  const VictimsListScreen({super.key});

  @override
  State<VictimsListScreen> createState() => _VictimsListScreenState();
}

class _VictimsListScreenState extends State<VictimsListScreen> {
  Timer? _pollingTimer;
  Timer? _uiRefreshTimer;
  List<Victim> _victims = [];
  bool _loading = true;
  String? _errorMessage;

  bool _useMockData = true;

  Set<int> _previousRedIds = {};
  Set<int> _previousOfflineIds = {};
  Set<int> _previousLowBatteryIds = {};
  final AudioPlayer _alertPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    MockDataService.instance.start(); // no-op if already running elsewhere
    // Listen directly to the service instead of polling on our own timer —
    // this guarantees we update at the EXACT same instant as every other
    // screen (Flood Status, any open Dashboard), rather than each screen
    // independently polling on its own schedule and drifting apart.
    MockDataService.instance.addListener(_onMockDataChanged);
    _pullMockData();
    // Still need a timer for the real-backend path, since that has no
    // push-notification mechanism of its own.
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_useMockData) _fetchVictims();
    });
    // Offline status depends purely on wall-clock time, not on new data
    // arriving — this forces a re-render periodically so "last seen Xs
    // ago" and the offline threshold stay accurate even if nothing new
    // has come in.
    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
      _checkForNewCritical();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _uiRefreshTimer?.cancel();
    MockDataService.instance.removeListener(_onMockDataChanged);
    _alertPlayer.dispose();
    super.dispose();
  }

  void _onMockDataChanged() {
    if (_useMockData) _pullMockData();
  }

  Future<void> _fetchVictims() async {
    try {
      final response = await http
          .get(Uri.parse('$kApiBaseUrl/victims'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _victims = data.map((v) => Victim.fromJson(v)).toList();
          _loading = false;
          _errorMessage = null;
        });
        _checkForNewCritical();
      } else {
        setState(() {
          _errorMessage = 'Server returned ${response.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Cannot reach backend: $e';
        _loading = false;
      });
    }
  }

  /// Reads the current state of the app-wide simulation — does NOT generate
  /// new data itself, since MockDataService.instance already keeps ticking
  /// on its own in the background regardless of this screen's lifecycle.
  void _pullMockData() {
    setState(() {
      _victims = MockDataService.instance.victims;
      _loading = false;
      _errorMessage = null;
    });
    _checkForNewCritical();
  }

  /// Compares this update's CRITICAL DISTRESS, OFFLINE, and LOW BATTERY
  /// contents against last time — if anyone NEW shows up in any of them,
  /// fires a vibration + one play-through of the alarm sound + a local
  /// notification. Also auto-clears acknowledgment for anyone who's exited
  /// red.
  void _checkForNewCritical() {
    final currentRedIds = _victims
        .where((v) => v.bucket == "red")
        .map((v) => v.id)
        .toSet();
    final currentOfflineIds = _victims
        .where(isVictimOffline)
        .map((v) => v.id)
        .toSet();
    final currentLowBatteryIds = _victims
        .where(isVictimLowBattery)
        .map((v) => v.id)
        .toSet();

    final newlyCritical = currentRedIds.difference(_previousRedIds);
    final newlyOffline = currentOfflineIds.difference(_previousOfflineIds);
    final newlyLowBattery = currentLowBatteryIds.difference(
      _previousLowBatteryIds,
    );
    final exitedRed = _previousRedIds.difference(currentRedIds);

    for (final id in exitedRed) {
      AcknowledgeService.instance.clear(id, syncToBackend: !_useMockData);
    }

    if (newlyCritical.isNotEmpty) {
      final names = _victims
          .where((v) => newlyCritical.contains(v.id))
          .map((v) => v.name)
          .join(", ");
      _triggerAlert(
        title: "Critical Distress",
        body: "$names now in critical distress",
      );
    }
    if (newlyOffline.isNotEmpty) {
      final names = _victims
          .where((v) => newlyOffline.contains(v.id))
          .map((v) => v.name)
          .join(", ");
      _triggerAlert(title: "Device Offline", body: "$names stopped reporting");
    }
    if (newlyLowBattery.isNotEmpty) {
      final names = _victims
          .where((v) => newlyLowBattery.contains(v.id))
          .map((v) => v.name)
          .join(", ");
      _triggerAlert(title: "Low Battery", body: "$names battery running low");
    }

    _previousRedIds = currentRedIds;
    _previousOfflineIds = currentOfflineIds;
    _previousLowBatteryIds = currentLowBatteryIds;
  }

  Future<void> _triggerAlert({
    required String title,
    required String body,
  }) async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(
        pattern: [0, 500, 200, 500, 200, 800],
        intensities: [0, 255, 0, 255, 0, 255],
      );
    }
    await _alertPlayer.stop();
    await _alertPlayer.setReleaseMode(
      ReleaseMode.release,
    ); // play once, don't loop
    await _alertPlayer.play(AssetSource('audio/alarm.wav'));
    await NotificationService.instance.showAlert(title: title, body: body);
  }

  void _toggleMockData(bool value) {
    setState(() => _useMockData = value);
    if (value) {
      _pullMockData();
    } else {
      _fetchVictims(); // switch back to real data immediately
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "POOL STATUS",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1A1A1A),
        actions: [
          Row(
            children: [
              const Text("Mock Data", style: TextStyle(fontSize: 12)),
              Switch(
                value: _useMockData,
                onChanged: _toggleMockData,
                activeThumbColor: const Color(0xFF00E5FF),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _useMockData ? _pullMockData : _fetchVictims,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, color: Colors.white38, size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchVictims,
                child: const Text("Retry"),
              ),
            ],
          ),
        ),
      );
    }

    if (_victims.isEmpty) {
      return const Center(
        child: Text(
          "No victims registered yet.\nRegister one via POST /victims.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    final offlineVictims = _victims.where(isVictimOffline).toList()
      ..sort(
        (a, b) => a.latestTelemetry!.timestamp.compareTo(
          b.latestTelemetry!.timestamp,
        ),
      );
    final lowBatteryVictims =
        _victims
            .where((v) => isVictimLowBattery(v) && !isVictimOffline(v))
            .toList()
          ..sort(
            (a, b) => (a.latestTelemetry?.batteryPct ?? 100).compareTo(
              b.latestTelemetry?.batteryPct ?? 100,
            ),
          );
    final redVictims =
        _victims.where((v) => v.bucket == "red" && !isVictimOffline(v)).toList()
          ..sort(
            (a, b) => (b.latestTelemetry?.urgencyScore ?? 0).compareTo(
              a.latestTelemetry?.urgencyScore ?? 0,
            ),
          );
    final yellowVictims =
        _victims
            .where((v) => v.bucket == "yellow" && !isVictimOffline(v))
            .toList()
          ..sort(
            (a, b) => (b.latestTelemetry?.urgencyScore ?? 0).compareTo(
              a.latestTelemetry?.urgencyScore ?? 0,
            ),
          );

    return Column(
      children: [
        // Summary bar — active device count
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.sensors, color: Color(0xFF00E5FF), size: 22),
                const SizedBox(width: 10),
                Text(
                  "ACTIVE DEVICES: ${_victims.length}",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              buildAlertSection(
                context: context,
                title: "OFFLINE",
                color: Colors.grey,
                victims: offlineVictims,
                onTapVictim: (ctx, v) => Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) =>
                        DashboardScreen(victimId: v.id, victimName: v.name),
                  ),
                ),
                showLastSeen: true,
              ),
              if (offlineVictims.isNotEmpty &&
                  (redVictims.isNotEmpty ||
                      yellowVictims.isNotEmpty ||
                      lowBatteryVictims.isNotEmpty))
                const SizedBox(height: 12),
              buildAlertSection(
                context: context,
                title: "CRITICAL DISTRESS",
                color: const Color(0xFFFF1744),
                victims: redVictims,
                onTapVictim: (ctx, v) => Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) =>
                        DashboardScreen(victimId: v.id, victimName: v.name),
                  ),
                ),
                showAcknowledge: true,
                syncAcknowledgeToBackend: !_useMockData,
              ),
              if (redVictims.isNotEmpty && yellowVictims.isNotEmpty)
                const SizedBox(height: 12),
              buildAlertSection(
                context: context,
                title: "WARNING",
                color: const Color(0xFFFFEA00),
                victims: yellowVictims,
                onTapVictim: (ctx, v) => Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) =>
                        DashboardScreen(victimId: v.id, victimName: v.name),
                  ),
                ),
              ),
              if (yellowVictims.isNotEmpty && lowBatteryVictims.isNotEmpty)
                const SizedBox(height: 12),
              buildAlertSection(
                context: context,
                title: "LOW BATTERY",
                color: Colors.orange,
                victims: lowBatteryVictims,
                onTapVictim: (ctx, v) => Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) =>
                        DashboardScreen(victimId: v.id, victimName: v.name),
                  ),
                ),
                showBattery: true,
              ),
              if (redVictims.isEmpty &&
                  yellowVictims.isEmpty &&
                  offlineVictims.isEmpty &&
                  lowBatteryVictims.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(
                    child: Text(
                      "All swimmers stable.\nNo red or yellow alerts right now.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// POOL SKETCH SCREEN — shows the pool outline with a star at the victim's
// precise position, opened by tapping the pool zone panel on the dashboard
// ---------------------------------------------------------------------------

class PoolSketchScreen extends StatelessWidget {
  final String victimName;
  final double? xNorm; // 0.0-1.0 across pool width
  final double? yNorm; // 0.0-1.0 along pool length
  final String zoneLabel;

  const PoolSketchScreen({
    super.key,
    required this.victimName,
    required this.xNorm,
    required this.yNorm,
    required this.zoneLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("$victimName — POOL LOCATION"),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Text(
              zoneLabel,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Center(
                child: AspectRatio(
                  // Pool width x length aspect ratio — landscape orientation
                  aspectRatio: kPoolWidthM / kPoolLengthM,
                  child: CustomPaint(
                    painter: _PoolPainter(xNorm: xNorm, yNorm: yNorm),
                    child: Container(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (xNorm == null || yNorm == null)
              const Text(
                "No precise position available (no GPS fix or outside pool bounds).",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}

class _PoolPainter extends CustomPainter {
  final double? xNorm;
  final double? yNorm;

  _PoolPainter({required this.xNorm, required this.yNorm});

  @override
  void paint(Canvas canvas, Size size) {
    final poolPaint = Paint()
      ..color = const Color(0xFF0288D1).withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final dividerPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));
    canvas.drawRRect(rrect, poolPaint);
    canvas.drawRRect(rrect, borderPaint);

    // Draw the 3x2 zone grid lines for visual reference
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      dividerPaint,
    );
    canvas.drawLine(
      Offset(0, size.height / 3),
      Offset(size.width, size.height / 3),
      dividerPaint,
    );
    canvas.drawLine(
      Offset(0, 2 * size.height / 3),
      Offset(size.width, 2 * size.height / 3),
      dividerPaint,
    );

    // Shallow-end label at top, deep-end at bottom
    _drawLabel(canvas, "SHALLOW", Offset(size.width / 2, 12));
    _drawLabel(canvas, "DEEP", Offset(size.width / 2, size.height - 20));

    // Plot the victim's star, if we have a position
    if (xNorm != null && yNorm != null) {
      final dx = xNorm!.clamp(0.0, 1.0) * size.width;
      final dy = yNorm!.clamp(0.0, 1.0) * size.height;
      _drawStar(canvas, Offset(dx, dy), 18, const Color(0xFFFF1744));
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset center) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 10,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Color color) {
    final path = Path();
    const points = 5;
    for (int i = 0; i < points * 2; i++) {
      final r = (i.isEven) ? radius : radius / 2.5;
      final angle = (pi / points) * i - pi / 2;
      final point = Offset(
        center.dx + r * cos(angle),
        center.dy + r * sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(path, glowPaint);

    final starPaint = Paint()..color = color;
    canvas.drawPath(path, starPaint);
  }

  @override
  bool shouldRepaint(covariant _PoolPainter oldDelegate) =>
      oldDelegate.xNorm != xNorm || oldDelegate.yNorm != yNorm;
}

// ---------------------------------------------------------------------------
// FLOOD MAP SCREEN — real OpenStreetMap view with a pin at the victim's
// actual GPS location. Opened by tapping the Location panel on the
// Dashboard when isFloodMode is true. Uses flutter_map (free, no API key —
// tiles come from OpenStreetMap's public tile server).
// ---------------------------------------------------------------------------

class FloodMapScreen extends StatelessWidget {
  final String victimName;
  final double? latitude;
  final double? longitude;

  const FloodMapScreen({
    super.key,
    required this.victimName,
    required this.latitude,
    required this.longitude,
  });

  @override
  Widget build(BuildContext context) {
    final hasFix = latitude != null && longitude != null;

    return Scaffold(
      appBar: AppBar(
        title: Text("$victimName — REAL LOCATION"),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: hasFix
          ? FlutterMap(
              options: MapOptions(
                initialCenter: latlong.LatLng(latitude!, longitude!),
                initialZoom: 16,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  // Required by OSM's tile usage policy — identifies your
                  // app to their servers. Update if you rename the project.
                  userAgentPackageName: 'com.ananth.tritonApp',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: latlong.LatLng(latitude!, longitude!),
                      width: 44,
                      height: 44,
                      child: const Icon(
                        Icons.location_pin,
                        color: Color(0xFFFF1744),
                        size: 44,
                      ),
                    ),
                  ],
                ),
                // Required attribution per OpenStreetMap's tile usage policy —
                // do not remove when using the free public tile server.
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      'OpenStreetMap contributors',
                      onTap: () {},
                    ),
                  ],
                ),
              ],
            )
          : const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  "No GPS fix available for this victim right now.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ),
      floatingActionButton: hasFix
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFFFF1744),
              icon: const Icon(Icons.directions, color: Colors.white),
              label: const Text(
                "GET DIRECTIONS",
                style: TextStyle(color: Colors.white),
              ),
              onPressed: () => openDirections(context, latitude!, longitude!),
            )
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// DASHBOARD SCREEN — detail view for one victim
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// BPM TREND CHART — simple custom-painted line chart, no charting package
// needed. Plots recent heart-rate readings so a responder can see "this has
// been climbing for the last few minutes" instead of only a single snapshot.
// ---------------------------------------------------------------------------

class BpmTrendChart extends StatelessWidget {
  final List<double> values; // oldest first
  final Color lineColor;

  const BpmTrendChart({
    super.key,
    required this.values,
    required this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return const Center(
        child: Text(
          "Collecting data for trend chart...",
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      );
    }
    return CustomPaint(
      painter: _BpmTrendPainter(values: values, lineColor: lineColor),
      child: Container(),
    );
  }
}

class _BpmTrendPainter extends CustomPainter {
  final List<double> values;
  final Color lineColor;

  _BpmTrendPainter({required this.values, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final range = (maxVal - minVal).clamp(1.0, double.infinity);

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final normalized = (values[i] - minVal) / range;
      final y =
          size.height -
          (normalized * size.height * 0.85) -
          (size.height * 0.075);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Faint fill under the line
    final fillPath = Path()
      ..addPath(path, Offset.zero)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()..color = lineColor.withValues(alpha: 0.12),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dot on the most recent point
    final lastX = size.width;
    final lastNormalized = (values.last - minVal) / range;
    final lastY =
        size.height -
        (lastNormalized * size.height * 0.85) -
        (size.height * 0.075);
    canvas.drawCircle(Offset(lastX, lastY), 4, Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(covariant _BpmTrendPainter oldDelegate) =>
      oldDelegate.values != values;
}

class DashboardScreen extends StatefulWidget {
  final int victimId;
  final String victimName;
  final bool isFloodMode;

  const DashboardScreen({
    super.key,
    required this.victimId,
    required this.victimName,
    this.isFloodMode = false,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _pollingTimer;
  bool _useMockData = true;

  final AudioPlayer _alarmPlayer = AudioPlayer();
  bool _alarmPlaying = false;

  String deviceStatus = "STABLE";
  double currentBpm = 72.0;
  int currentPiezoDepth = 1200;
  String currentPoolZone = "No GPS Fix";
  double? currentAge;
  double? currentBatteryPct;
  double? currentBatteryDrainPctPerMin;
  double currentUrgencyScore = 0.0;
  double? currentPoolXNorm;
  double? currentPoolYNorm;
  double? currentLatitude;
  double? currentLongitude;
  DateTime _lastUpdateTimestamp = DateTime.now();
  List<double> _bpmHistory = [];

  @override
  void initState() {
    super.initState();
    if (_useMockData) {
      MockDataService.instance.start(); // no-op if already running elsewhere
      // Listen directly instead of polling on our own separate timer — this
      // is what was causing the Dashboard to drift out of sync with the
      // list screens (this was polling every 2s, the service ticks every
      // 3s, so the two would never quite line up).
      MockDataService.instance.addListener(_onMockDataChanged);
      _generateMockTelemetry(); // populate immediately
    } else {
      _fetchLiveTelemetry();
    }
    // Still needed for the real-backend path only, since that has no
    // push-notification mechanism of its own.
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_useMockData) _fetchLiveTelemetry();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    MockDataService.instance.removeListener(_onMockDataChanged);
    _alarmPlayer.dispose();
    super.dispose();
  }

  void _onMockDataChanged() {
    if (_useMockData) _generateMockTelemetry();
  }

  void _toggleMockData(bool value) {
    setState(() => _useMockData = value);
    if (value) {
      MockDataService.instance.start();
      MockDataService.instance.addListener(_onMockDataChanged);
      _generateMockTelemetry();
    } else {
      MockDataService.instance.removeListener(_onMockDataChanged);
      _fetchLiveTelemetry();
    }
  }

  /// Reads this specific victim's current state from the app-wide
  /// MockDataService, so the Dashboard always matches exactly what the list
  /// screens (Pool Status / Flood Status) are showing for this same band —
  /// instead of independently randomizing disconnected data.
  void _generateMockTelemetry() {
    MockDataService.instance.start(); // no-op if already running elsewhere
    final mockVictim = MockDataService.instance.getById(widget.victimId);
    final t = mockVictim?.latestTelemetry;
    if (t == null) return; // service hasn't ticked yet or victim not found

    final String previousBucket = _bucket;

    setState(() {
      currentBpm = t.bpm;
      currentPiezoDepth = t.piezoDepth;
      currentPoolZone = t.poolZone;
      currentAge = t.ageYears;
      currentBatteryPct = t.batteryPct;
      currentBatteryDrainPctPerMin = t.batteryDrainPctPerMin;
      currentUrgencyScore = t.urgencyScore;
      currentPoolXNorm = t.poolXNorm;
      currentPoolYNorm = t.poolYNorm;
      currentLatitude = t.latitude;
      currentLongitude = t.longitude;
      _lastUpdateTimestamp = t.timestamp;
      _bpmHistory = MockDataService.instance
          .getHistory(widget.victimId)
          .map((h) => h.bpm)
          .toList();
      _updateTriageStatus();
    });

    _handleHapticTransition(previousBucket, _bucket);
  }

  Future<void> _fetchLiveTelemetry() async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '$kApiBaseUrl/victims/${widget.victimId}/telemetry?limit=20',
            ),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (data.isEmpty) return;

        // Backend returns most-recent-first; .first is the latest reading,
        // reversed gives oldest-first for the trend chart.
        final readings = data.map((j) => Telemetry.fromJson(j)).toList();
        final latest = readings.first;
        final String previousBucket = _bucket;

        setState(() {
          currentBpm = latest.bpm;
          currentPiezoDepth = latest.piezoDepth;
          currentPoolZone = latest.poolZone;
          currentAge = latest.ageYears;
          currentBatteryPct = latest.batteryPct;
          currentBatteryDrainPctPerMin = latest.batteryDrainPctPerMin;
          currentUrgencyScore = latest.urgencyScore;
          currentPoolXNorm = latest.poolXNorm;
          currentPoolYNorm = latest.poolYNorm;
          currentLatitude = latest.latitude;
          currentLongitude = latest.longitude;
          _lastUpdateTimestamp = latest.timestamp;
          _bpmHistory = readings.reversed.map((r) => r.bpm).toList();
          _updateTriageStatus();
        });

        _handleHapticTransition(previousBucket, _bucket);
      } else {
        debugPrint("API returned ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("API Connection failure: $e");
    }
  }

  void _updateTriageStatus() {
    // deviceStatus here is used ONLY to detect which raw threshold caused
    // an alert, for cause-specific wording in _alertDisplayText. Color and
    // vibration are driven separately by _bucket (the urgency-score-based
    // classification), so this screen always agrees with the Pool Status
    // screen's red/yellow sections.
    if (currentPiezoDepth > 3500 ||
        currentBpm > 140 ||
        (currentBpm < 45 && currentBpm > 0)) {
      deviceStatus = "CRITICAL DISTRESS";
    } else if (currentPiezoDepth > 2200) {
      deviceStatus = "WARNING: HIGH WATER";
    } else {
      deviceStatus = "SYSTEM STABLE";
    }
  }

  /// The single source of truth for this screen's severity — same
  /// thresholds/logic as the Pool Status screen's red/yellow sections.
  String get _bucket => bucketForScore(currentUrgencyScore);

  bool get _isOffline =>
      DateTime.now().difference(_lastUpdateTimestamp).inSeconds >
      AppSettings.instance.offlineThresholdSeconds;

  Color get statusColor => _isOffline ? Colors.grey : colorForBucket(_bucket);

  /// Display-only text for the status box. Prefers the specific raw-sensor
  /// cause (high BPM, low BPM, too deep) when one of those actually
  /// triggered; falls back to a generic elevated-risk message if the
  /// urgency-score bucket is red/yellow for other reasons (e.g. age or
  /// battery risk) so the text never contradicts the box's color.
  String get _alertDisplayText {
    if (_isOffline) {
      return "OFFLINE — LAST SEEN ${formatLastSeen(_lastUpdateTimestamp).toUpperCase()}";
    }
    if (deviceStatus == "CRITICAL DISTRESS") {
      if (currentBpm > 140) return "DANGER: HIGH BPM";
      if (currentBpm < 45 && currentBpm > 0) return "DANGER: LOW BPM";
      return "DANGER: TOO DEEP"; // triggered by depth alone, BPM was normal
    } else if (deviceStatus == "WARNING: HIGH WATER") {
      return "DANGER: TOO DEEP";
    }
    // Raw thresholds look normal — fall back to the bucket so the text
    // never contradicts the box's color (e.g. yellow from age/battery risk
    // alone, with otherwise-normal BPM and depth).
    if (_bucket == "red") return "DANGER: ELEVATED RISK";
    if (_bucket == "yellow") return "WARNING: ELEVATED RISK";
    return "SYSTEM STABLE";
  }

  /// Vibrates + starts the alarm when entering the red bucket; stops both
  /// when leaving it. Yellow gets its color from statusColor but never
  /// vibrates or sounds the alarm — only red does.
  Future<void> _handleHapticTransition(
    String previousBucket,
    String newBucket,
  ) async {
    if (newBucket == "red" && previousBucket != "red") {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(
          pattern: [0, 500, 200, 500, 200, 800],
          intensities: [0, 255, 0, 255, 0, 255],
        );
      }
      if (!_alarmPlaying) {
        _alarmPlaying = true;
        await _alarmPlayer.setReleaseMode(ReleaseMode.loop);
        await _alarmPlayer.play(AssetSource('audio/alarm.wav'));
      }
    } else if (newBucket != "red" && previousBucket == "red") {
      Vibration.cancel();
      if (_alarmPlaying) {
        _alarmPlaying = false;
        await _alarmPlayer.stop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TridentIcon(size: 20, color: Color(0xFF00E5FF)),
            const SizedBox(width: 8),
            Text(
              widget.victimName.toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1A1A1A),
        actions: [
          Row(
            children: [
              const Text("Mock Data", style: TextStyle(fontSize: 12)),
              Switch(
                value: _useMockData,
                onChanged: _toggleMockData,
                activeThumbColor: const Color(0xFF00E5FF),
              ),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Header — danger alert + matching urgency score
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor, width: 2),
              ),
              child: Column(
                children: [
                  Text(
                    _alertDisplayText,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: statusColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Urgency Score: ${currentUrgencyScore.toStringAsFixed(0)} / 100",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: statusColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Vitals + Age + Battery Grid
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.1,
                children: [
                  _buildSensorCard(
                    "HEART RATE",
                    "${currentBpm.toStringAsFixed(0)} BPM",
                    Icons.favorite,
                    Colors.pinkAccent,
                  ),
                  _buildSensorCard(
                    "PIEZO DEPTH",
                    "$currentPiezoDepth / 4095",
                    Icons.layers,
                    Colors.blueAccent,
                  ),
                  _buildSensorCard(
                    "AGE",
                    currentAge != null
                        ? "${currentAge!.toStringAsFixed(0)} yrs"
                        : "—",
                    Icons.person,
                    Colors.amberAccent,
                  ),
                  _buildBatteryCard(),
                ],
              ),
            ),

            // BPM Trend Chart — shows the recent history instead of just
            // a single snapshot, so a climbing/falling trend is visible.
            Container(
              height: 90,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "HEART RATE TREND",
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: BpmTrendChart(
                      values: _bpmHistory,
                      lineColor: statusColor,
                    ),
                  ),
                ],
              ),
            ),

            // Location Panel — Pool Zone (tap opens pool sketch) for pool
            // victims, or real GPS location (tap opens an OpenStreetMap
            // view) for flood victims.
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (widget.isFloodMode) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FloodMapScreen(
                        victimName: widget.victimName,
                        latitude: currentLatitude,
                        longitude: currentLongitude,
                      ),
                    ),
                  );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PoolSketchScreen(
                        victimName: widget.victimName,
                        xNorm: currentPoolXNorm,
                        yNorm: currentPoolYNorm,
                        zoneLabel: currentPoolZone,
                      ),
                    ),
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.isFloodMode ? Icons.map : Icons.pool,
                      color: const Color(0xFF00E5FF),
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.isFloodMode
                                ? "LOCATION — tap for map"
                                : "POOL ZONE — tap for precise location",
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.isFloodMode
                                ? (currentLatitude != null &&
                                          currentLongitude != null
                                      ? "${currentLatitude!.toStringAsFixed(5)}, ${currentLongitude!.toStringAsFixed(5)}"
                                      : "No GPS Fix")
                                : currentPoolZone,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white38),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Manual Panic Trigger Button
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF1744),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                final String previousBucket = _bucket;
                setState(() {
                  currentPiezoDepth = 4000;
                  // Force the local urgency score into the red range too —
                  // urgency_score normally comes from the server, but a
                  // manual SOS press should immediately simulate red
                  // (color + vibrate) rather than waiting on the next poll.
                  currentUrgencyScore = 100.0;
                  _updateTriageStatus();
                });
                _handleHapticTransition(previousBucket, _bucket);
              },
              icon: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
              ),
              label: const Text(
                "MANUAL SOS OVERRIDE",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorCard(
    String title,
    String value,
    IconData icon,
    Color themeColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: themeColor, size: 30),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// Battery card with a small drain-rate indicator underneath the percentage.
  Widget _buildBatteryCard() {
    final pct = currentBatteryPct;
    final drain = currentBatteryDrainPctPerMin;

    Color batteryColor = Colors.greenAccent;
    if (pct != null) {
      if (pct < 20) {
        batteryColor = const Color(0xFFFF1744);
      } else if (pct < 50) {
        batteryColor = const Color(0xFFFFEA00);
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.battery_full, color: batteryColor, size: 30),
          const SizedBox(height: 8),
          const Text(
            "BATTERY",
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            pct != null ? "${pct.toStringAsFixed(0)}%" : "—",
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            drain != null
                ? "−${drain.toStringAsFixed(2)}%/min"
                : "no drain data",
            style: TextStyle(
              fontSize: 10,
              color: (drain != null && drain > 1.0)
                  ? const Color(0xFFFF1744)
                  : Colors.white38,
            ),
          ),
        ],
      ),
    );
  }
}
