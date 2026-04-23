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

import '../../core/app_strings.dart';
import '../../core/constants.dart';
import '../../providers/sync_provider.dart';
import '../../database/database.dart';
import '../../database/dao/customer_dao.dart';
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
    final s = context.read<AppStrings>();
    final v = value?.trim() ?? '';
    if (v.isEmpty) return s.isEnglish ? 'Please enter API Base URL' : '請輸入 API Base URL';
    if (!v.startsWith('http://') && !v.startsWith('https://')) {
      return s.isEnglish ? 'Must start with http:// or https://' : '必須以 http:// 或 https:// 開頭';
    }
    if (v.endsWith('/')) return s.isEnglish ? 'No trailing slash /' : '結尾請勿加斜線 /';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final sync = context.read<SyncProvider>();
      final s = context.read<AppStrings>();
      await sync.updateApiBaseUrl(_urlController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.isEnglish ? 'Saved: ${_urlController.text.trim()}' : '已儲存：${_urlController.text.trim()}'),
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
    final s = context.read<AppStrings>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.devResetApiTitle),
        content: Text(s.devResetApiBody(kApiBaseUrl)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.btnResetDefault),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await context.read<SyncProvider>().resetApiBaseUrl();
    if (mounted) {
      _urlController.text = kApiBaseUrl;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.devResetApiDone)),
      );
    }
  }

  Future<void> _cleanup() async {
    final s = context.read<AppStrings>();
    setState(() => _isCleaning = true);
    try {
      final sync = context.read<SyncProvider>();
      final result = await sync.performCleanup();
      if (!mounted) return;
      final softDeleted = result['deletedSoftDeleted'] as Map<String, dynamic>? ?? {};
      final softCount = softDeleted.values.fold<int>(0, (s, v) => s + (v as int));
      final msg = s.devCleanupSuccess(
        result['deletedProcessedOps'] as int? ?? 0,
        softCount,
        result['localDeletedSucceeded'] as int? ?? 0,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.isEnglish ? 'Cleanup failed: $e' : '清理失敗：$e'), backgroundColor: Colors.red),
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

    final s = context.watch<AppStrings>();

    return Scaffold(
      appBar: AppBar(
        title: Text(s.devTitle),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 語言切換 ────────────────────────────────────────────────
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.devSectionLang),
                subtitle: Text(s.devSwitchLang),
                value: s.isEnglish,
                onChanged: (v) async => context.read<AppStrings>().setEnglish(v),
              ),
              const Divider(),
              const SizedBox(height: 12),

              // 編譯期預設
              Text(
                s.devSectionCompile,
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
                      s.devCurrentCustomUrl,
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
                      label: Text(s.btnResetDefault),
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
                          label: Text(s.btnSaveSettings),
                        ),
                ],
              ),

              // ── Admin 功能（Admin Only）────────────────────────────────
              if (isAdmin) ...[
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  s.devSectionImport,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.importTitle, style: const TextStyle(fontWeight: FontWeight.w500)),
                          Text(
                            s.isEnglish ? 'Initial import of products, customers, and inventory.' : '上線前初始匯入產品、客戶、庫存資料。',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
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
                      label: Text(s.btnOpenImport),
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
                  s.devSectionMaintain,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                // ── 清理舊記錄 ──
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.devCleanupTitle, style: const TextStyle(fontWeight: FontWeight.w500)),
                          Text(
                            s.devCleanupDesc,
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
                            label: Text(s.btnRunCleanup),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                          ),
                  ],
                ),
                const SizedBox(height: 20),
                // ── 清空本地客戶 ──
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.devClearCustTitle, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.red)),
                          Text(
                            s.devClearCustDesc,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final db = context.read<AppDatabase>();
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(s.devConfirmClearTitle),
                            content: Text(s.devConfirmClearBody),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.btnCancel)),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text(s.devClearCustTitle, style: const TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await db.hardDeleteAllLocalCustomers();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(s.devClearCustSuccess), backgroundColor: Colors.orange),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.no_accounts_outlined, size: 16),
                      label: Text(s.btnDelete),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
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
