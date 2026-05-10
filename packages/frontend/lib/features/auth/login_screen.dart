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
  bool _humanVerified = false;

  Future<void> _login() async {
    final s = context.read<AppStrings>();
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.errEmptyCredentials)),
      );
      return;
    }
    if (!_humanVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please verify you are human')),
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

    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: AppTheme.backgroundGradient,
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

                        // App logo
                        Center(
                          child: Image.asset(
                            'assets/images/LOGIN.png',
                            width: 120,
                            height: 120,
                            fit: BoxFit.contain,
                          ),
                        ),
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
                        const SizedBox(height: 16),

                        // Cloudflare human verification
                        _HumanVerifyWidget(
                          checked: _humanVerified,
                          onTap: () => setState(
                              () => _humanVerified = !_humanVerified),
                        ),
                        const SizedBox(height: 20),

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

          // Settings icon — top right overlay (must be last child to receive touches)
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
// _HumanVerifyWidget — Cloudflare Turnstile-style checkbox
// ==============================================================================

class _HumanVerifyWidget extends StatelessWidget {
  final bool checked;
  final VoidCallback onTap;

  const _HumanVerifyWidget({required this.checked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFD9D9D9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: checked ? const Color(0xFF009E60) : Colors.white,
                border: Border.all(
                  color: checked
                      ? const Color(0xFF009E60)
                      : const Color(0xFFBDBDBD),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
              child: checked
                  ? const Icon(Icons.check, color: Colors.white, size: 20)
                  : null,
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Verify you are human',
                style: TextStyle(fontSize: 14, color: Color(0xFF3D3D3D)),
              ),
            ),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CloudflareIcon(size: 22),
                    SizedBox(width: 4),
                    Text(
                      'Cloudflare',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF404040),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Privacy · Terms',
                  style: TextStyle(fontSize: 9, color: Color(0xFF888888)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CloudflareIcon extends StatelessWidget {
  final double size;
  const _CloudflareIcon({this.size = 22});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.7,
      child: CustomPaint(painter: _CloudPainter()),
    );
  }
}

class _CloudPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()..style = PaintingStyle.fill;

    // Orange cloud body
    paint.color = const Color(0xFFF6821F);
    final path = Path()
      ..moveTo(w * 0.18, h * 0.85)
      ..lineTo(w * 0.82, h * 0.85)
      ..quadraticBezierTo(w * 1.0, h * 0.85, w * 0.95, h * 0.6)
      ..quadraticBezierTo(w * 0.92, h * 0.38, w * 0.74, h * 0.38)
      ..quadraticBezierTo(w * 0.68, h * 0.05, w * 0.44, h * 0.10)
      ..quadraticBezierTo(w * 0.28, h * 0.14, w * 0.26, h * 0.38)
      ..quadraticBezierTo(w * 0.06, h * 0.36, w * 0.04, h * 0.60)
      ..quadraticBezierTo(w * 0.01, h * 0.85, w * 0.18, h * 0.85)
      ..close();
    canvas.drawPath(path, paint);

    // White highlight strip at bottom
    paint.color = Colors.white.withValues(alpha: 0.4);
    final strip = Path()
      ..moveTo(w * 0.20, h * 0.78)
      ..lineTo(w * 0.80, h * 0.78)
      ..quadraticBezierTo(w * 0.90, h * 0.78, w * 0.88, h * 0.68)
      ..lineTo(w * 0.12, h * 0.68)
      ..quadraticBezierTo(w * 0.10, h * 0.78, w * 0.20, h * 0.78)
      ..close();
    canvas.drawPath(strip, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
