import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入帳號與密碼')),
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
          const SnackBar(content: Text('登入失敗，請檢查帳號密碼。')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('發生錯誤: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NJ Stream ERP — 登入'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '開發者設定',
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
                        TextField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: '帳號',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          decoration: const InputDecoration(
                            labelText: '密碼',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.password),
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
                            child: const Text('登入', style: TextStyle(fontSize: 16)),
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
