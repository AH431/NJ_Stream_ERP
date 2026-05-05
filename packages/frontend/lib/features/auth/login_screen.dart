import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../core/app_theme.dart';
import '../../providers/sync_provider.dart';
import '../settings/dev_settings_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _login() async {
    final s = context.read<AppStrings>();
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.errEmptyCredentials)),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final syncProvider = context.read<SyncProvider>();
      final success = await syncProvider.login(
        _usernameController.text,
        _passwordController.text,
      );
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.errLoginFailed)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.errLoginException(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final currentApiBaseUrl = context.watch<SyncProvider>().currentApiBaseUrl;
    final isUsingLocalhost = currentApiBaseUrl.contains('localhost');

    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Color(0xFFDDF3FB)],
              ),
            ),
          ),

          // Settings icon — top right overlay
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 4, top: 4),
                child: IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  color: AppTheme.primaryDark,
                  tooltip: s.menuDevSettings,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DevSettingsScreen()),
                  ),
                ),
              ),
            ),
          ),

          // Main content
          if (context.watch<SyncProvider>().isInitializing)
            const Center(child: CircularProgressIndicator())
          else
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    left: 28,
                    right: 28,
                    top: 24,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),

                        // Shield logo
                        const Center(child: _PyStreamLogo(size: 90)),
                        const SizedBox(height: 18),

                        // Brand name
                        const Text(
                          'NJ Stream ERP',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryDark,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Tagline
                        Text(
                          s.isEnglish
                              ? 'AI-Driven Supply Chain Intelligence'
                              : 'AI 驅動的供應鏈智慧管理',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF4A9EBA),
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 36),

                        // API server indicator
                        _ApiServerCard(
                          url: currentApiBaseUrl,
                          isLocalhost: isUsingLocalhost,
                          label: s.loginCurrentApiLabel,
                          localhostWarning: s.loginLocalhostWarning,
                        ),
                        const SizedBox(height: 20),

                        // Username field
                        TextField(
                          controller: _usernameController,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: s.loginFieldUsername,
                            prefixIcon:
                                const Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Password field
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _login(),
                          decoration: InputDecoration(
                            labelText: s.loginFieldPassword,
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => setState(() =>
                                  _obscurePassword = !_obscurePassword),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Login button / loading
                        if (_isLoading)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else
                          FilledButton(
                            onPressed: _login,
                            style: FilledButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Text(s.btnLogin),
                          ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

// ==============================================================================
// _PyStreamLogo — shield with circular-arrows icon
// ==============================================================================

class _PyStreamLogo extends StatelessWidget {
  final double size;
  const _PyStreamLogo({this.size = 90});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 1.12,
      child: CustomPaint(
        painter: _ShieldPainter(),
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(bottom: size * 0.06),
            child: SizedBox(
              width: size * 0.50,
              height: size * 0.50,
              child: CustomPaint(painter: _CircularArrowsPainter()),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = _buildPath(w, h);

    // Drop shadow
    canvas.drawPath(
      path.shift(const Offset(0, 4)),
      Paint()
        ..color = const Color(0xFF0077B6).withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // Gradient fill
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF48CAE4), Color(0xFF0077B6)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Subtle top highlight
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [Color(0x30FFFFFF), Color(0x00FFFFFF)],
        ).createShader(Rect.fromLTWH(0, 0, w, h * 0.55)),
    );
  }

  Path _buildPath(double w, double h) {
    return Path()
      ..moveTo(w * 0.50, h * 0.01)
      ..cubicTo(w * 0.68, h * 0.01, w * 0.97, h * 0.09, w * 0.97, h * 0.28)
      ..lineTo(w * 0.97, h * 0.55)
      ..cubicTo(w * 0.97, h * 0.79, w * 0.74, h * 0.93, w * 0.50, h * 0.99)
      ..cubicTo(w * 0.26, h * 0.93, w * 0.03, h * 0.79, w * 0.03, h * 0.55)
      ..lineTo(w * 0.03, h * 0.28)
      ..cubicTo(w * 0.03, h * 0.09, w * 0.32, h * 0.01, w * 0.50, h * 0.01)
      ..close();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _CircularArrowsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.34;
    const arcGap = 0.40; // radians gap between each of the 3 arcs

    final strokeW = size.width * 0.115;
    final arcPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round;
    final arrowPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW * 0.85
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 3; i++) {
      final base = (i * 2 * math.pi / 3) - math.pi / 2;
      final start = base + arcGap / 2;
      const sweep = (2 * math.pi / 3) - arcGap;

      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        start,
        sweep,
        false,
        arcPaint,
      );

      // Arrowhead at arc tip
      final tipAngle = start + sweep;
      final tipX = cx + r * math.cos(tipAngle);
      final tipY = cy + r * math.sin(tipAngle);
      final tangent = tipAngle + math.pi / 2;
      final arrowLen = size.width * 0.14;

      canvas.drawLine(
        Offset(tipX, tipY),
        Offset(
          tipX + arrowLen * math.cos(tangent + math.pi * 0.78),
          tipY + arrowLen * math.sin(tangent + math.pi * 0.78),
        ),
        arrowPaint,
      );
      canvas.drawLine(
        Offset(tipX, tipY),
        Offset(
          tipX + arrowLen * math.cos(tangent - math.pi * 0.78),
          tipY + arrowLen * math.sin(tangent - math.pi * 0.78),
        ),
        arrowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ==============================================================================
// _ApiServerCard
// ==============================================================================

class _ApiServerCard extends StatelessWidget {
  final String url;
  final bool isLocalhost;
  final String label;
  final String localhostWarning;

  const _ApiServerCard({
    required this.url,
    required this.isLocalhost,
    required this.label,
    required this.localhostWarning,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor =
        isLocalhost ? Colors.orange.shade200 : const Color(0xFFCAE9F5);
    final bgColor =
        isLocalhost ? Colors.orange.shade50 : const Color(0xFFF0F9FF);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          SelectableText(
            url,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
          if (isLocalhost) ...[
            const SizedBox(height: 8),
            Text(
              localhostWarning,
              style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
            ),
          ],
        ],
      ),
    );
  }
}
