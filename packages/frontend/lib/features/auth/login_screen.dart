import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
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
      appBar: AppBar(
        title: Text(s.loginTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: s.menuDevSettings,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DevSettingsScreen()),
            ),
          ),
        ],
      ),
      resizeToAvoidBottomInset: true,
      body: context.watch<SyncProvider>().isInitializing
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    left: 24,
                    right: 24,
                    top: 24,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Image.asset('assets/images/app_icon.png', width: 80, height: 80),
                        const SizedBox(height: 32),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isUsingLocalhost
                                ? Colors.orange.shade50
                                : Colors.blueGrey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isUsingLocalhost
                                  ? Colors.orange.shade200
                                  : Colors.blueGrey.shade200,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.loginCurrentApiLabel,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                currentApiBaseUrl,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                ),
                              ),
                              if (isUsingLocalhost) ...[
                                const SizedBox(height: 8),
                                Text(
                                  s.loginLocalhostWarning,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade900,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: s.loginFieldUsername,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.person),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          decoration: InputDecoration(
                            labelText: s.loginFieldPassword,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.password),
                          ),
                          obscureText: true,
                          onSubmitted: (_) => _login(),
                        ),
                        const SizedBox(height: 32),
                        if (_isLoading)
                          const Center(child: CircularProgressIndicator())
                        else
                          FilledButton(
                            onPressed: _login,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Text(s.btnLogin, style: const TextStyle(fontSize: 16)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
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
