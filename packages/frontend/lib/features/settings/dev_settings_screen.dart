// ==============================================================================
// DevSettingsScreen — 開發者設定（Issue #36）
//
// 功能：
//   執行時修改 API Base URL，無需重新 build APK。
//   主要用途：Cloudflare Quick Tunnel 每次重啟都會產生新 URL，
//   可在此直接貼上新 URL 即可，免去 flutter run --dart-define 重建流程。
//
// 設計：
//   - URL 儲存於 FlutterSecureStorage（key: dev_api_base_url）
//   - 立即更新 Dio.options.baseUrl（不需重啟 App）
//   - Reset 按鈕恢復編譯期常數（kApiBaseUrl）
//   - 入口：LoginScreen AppBar（登入前）+ HomeScreen 溢出選單（登入後）
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../providers/sync_provider.dart';
import 'import_screen.dart';

class DevSettingsScreen extends StatefulWidget {
  const DevSettingsScreen({super.key});

  @override
  State<DevSettingsScreen> createState() => _DevSettingsScreenState();
}

class _DevSettingsScreenState extends State<DevSettingsScreen> {
  late final TextEditingController _urlController;
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  bool _isCleaning = false;

  @override
  void initState() {
    super.initState();
    final currentUrl = context.read<SyncProvider>().currentApiBaseUrl;
    _urlController = TextEditingController(text: currentUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------

  String? _validateUrl(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return '請輸入 API Base URL';
    if (!v.startsWith('http://') && !v.startsWith('https://')) {
      return '必須以 http:// 或 https:// 開頭';
    }
    if (v.endsWith('/')) return '結尾請勿加斜線 /';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final sync = context.read<SyncProvider>();
      await sync.updateApiBaseUrl(_urlController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已儲存：${_urlController.text.trim()}'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('重置 API URL'),
        content: const Text('將恢復為編譯期預設值：\n$kApiBaseUrl'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await context.read<SyncProvider>().resetApiBaseUrl();
    if (mounted) {
      _urlController.text = kApiBaseUrl;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已重置為預設 URL')),
      );
    }
  }

  Future<void> _cleanup() async {
    setState(() => _isCleaning = true);
    try {
      final sync = context.read<SyncProvider>();
      final result = await sync.performCleanup();
      if (!mounted) return;
      final softDeleted = result['deletedSoftDeleted'] as Map<String, dynamic>? ?? {};
      final msg = '後端清理：processed_ops ${result['deletedProcessedOps']} 筆，'
          '軟刪除 ${(softDeleted.values.fold<int>(0, (s, v) => s + (v as int)))} 筆；'
          '本地 succeeded ${result['localDeletedSucceeded']} 筆';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清理失敗：$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isCleaning = false);
    }
  }

  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    const defaultUrl = kApiBaseUrl;
    final sync = context.watch<SyncProvider>();
    final currentUrl = sync.currentApiBaseUrl;
    final isCustom = currentUrl != defaultUrl;
    final isAdmin = sync.role == 'admin';

    return Scaffold(
      appBar: AppBar(
        title: const Text('開發者設定'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 編譯期預設
              Text(
                '編譯期預設值',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 4),
              const Text(
                defaultUrl,
                style: TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
              const SizedBox(height: 20),

              // 目前狀態
              if (isCustom) ...[
                Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 14, color: Colors.indigo.shade400),
                    const SizedBox(width: 4),
                    Text(
                      '目前使用自訂 URL',
                      style: TextStyle(fontSize: 12, color: Colors.indigo.shade400),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // URL 輸入欄
              TextFormField(
                controller: _urlController,
                validator: _validateUrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'API Base URL',
                  hintText: 'https://xxxx.trycloudflare.com',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 24),

              // 按鈕列
              Row(
                children: [
                  if (isCustom)
                    OutlinedButton.icon(
                      onPressed: _isSaving ? null : _reset,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('重置為預設'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.grey),
                    ),
                  const Spacer(),
                  _isSaving
                      ? const SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : FilledButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.save_outlined, size: 16),
                          label: const Text('儲存'),
                        ),
                ],
              ),

              // ── Admin 功能（Admin Only）────────────────────────────────
              if (isAdmin) ...[
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  '資料匯入',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('CSV 資料匯入', style: TextStyle(fontWeight: FontWeight.w500)),
                          Text(
                            '上線前初始匯入產品、客戶、庫存資料。',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ImportScreen()),
                      ),
                      icon: const Icon(Icons.upload_file_outlined, size: 16),
                      label: const Text('開啟匯入'),
                    ),
                  ],
                ),

              // ── 清理舊記錄 ──────────────────────────────────────────
              ],
              if (isAdmin) ...[
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  '資料維護',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('清理舊記錄', style: TextStyle(fontWeight: FontWeight.w500)),
                          Text(
                            '刪除後端 30 天前的已處理記錄與軟刪除資料，\n及本地 7 天前的已完成同步記錄。',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _isCleaning
                        ? const SizedBox(
                            width: 24, height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : OutlinedButton.icon(
                            onPressed: _cleanup,
                            icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                            label: const Text('執行清理'),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                          ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
