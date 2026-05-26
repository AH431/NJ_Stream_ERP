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
  bool _isCleaning = false;
  bool _isForceFullSyncing = false;

  String? _tenantName;
  String? _tenantEmail;
  bool _isLoadingTenant = false;

  @override
  void initState() {
    super.initState();
    final sync = context.read<SyncProvider>();
    _urlController = TextEditingController(text: sync.currentApiBaseUrl);
    if (sync.isLoggedIn) _loadTenantInfo();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadTenantInfo() async {
    setState(() => _isLoadingTenant = true);
    try {
      final dio = context.read<SyncProvider>().authenticatedDio;
      final response = await dio.get<Map<String, dynamic>>('/api/v1/tenant');
      if (mounted) {
        setState(() {
          _tenantName  = response.data?['name'] as String?;
          _tenantEmail = response.data?['contactEmail'] as String?;
        });
      }
    } catch (_) {
      // 無法取得租戶資訊時靜默失敗（可能尚未登入）
    } finally {
      if (mounted) setState(() => _isLoadingTenant = false);
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

  Future<void> _forceFullSync() async {
    final s = context.read<AppStrings>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.devForceFullSyncConfirmTitle),
        content: Text(s.devForceFullSyncConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(s.btnForceFullSync),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isForceFullSyncing = true);
    try {
      await context.read<SyncProvider>().forceFullSync();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.devForceFullSyncSuccess), backgroundColor: Colors.green),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.isEnglish ? 'Full sync failed: $e' : '全量同步失敗：$e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isForceFullSyncing = false);
    }
  }

  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
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
              Row(
                children: [
                  Text(s.devSectionLang, style: Theme.of(context).textTheme.bodyLarge),
                  const Spacer(),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('中文')),
                      ButtonSegment(value: true, label: Text('English')),
                    ],
                    selected: {s.isEnglish},
                    onSelectionChanged: (v) async =>
                        context.read<AppStrings>().setEnglish(v.first),
                    showSelectedIcon: false,
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 12),

              // ── 公司資訊 ──────────────────────────────────────────────
              Text(
                s.devSectionCompany,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 12),
              if (_isLoadingTenant)
                const Center(
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else ...[
                _InfoRow(label: s.devCompanyName, value: _tenantName ?? s.devNotSet),
                const SizedBox(height: 8),
                _InfoRow(label: s.devContactEmail, value: _tenantEmail ?? s.devNotSet),
              ],

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
                const SizedBox(height: 20),
                // ── DB 重建全量同步 ──
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.devForceFullSyncTitle,
                              style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.red)),
                          Text(
                            s.devForceFullSyncDesc,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _isForceFullSyncing
                        ? const SizedBox(
                            width: 24, height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : OutlinedButton.icon(
                            onPressed: _forceFullSync,
                            icon: const Icon(Icons.sync_problem_outlined, size: 16),
                            label: Text(s.btnForceFullSync),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}
