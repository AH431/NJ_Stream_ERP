// ==============================================================================
// CustomerFormScreen — 新增客戶表單（含 Drift 本地寫入 + SyncProvider enqueue）
//
// 流程：
//   1. 使用者填寫表單並點擊儲存
//   2. 本地 id = SyncProvider.nextLocalId()（負數臨時 id）
//   3. 寫入 Drift customers 表
//   4. 排入 PendingOperations（operationType: create）
//   5. 關閉 screen，CustomerListScreen 的 StreamBuilder 自動更新
// ==============================================================================

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/dao/customer_dao.dart';
import '../../database/database.dart';
import '../../database/schema.dart';
import '../../providers/sync_provider.dart';

class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({super.key});

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _taxIdCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _taxIdCtrl.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // 儲存：本地 Drift 寫入 → enqueueCreate
  // --------------------------------------------------------------------------

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final db = context.read<AppDatabase>();
      final sync = context.read<SyncProvider>();
      final now = DateTime.now().toUtc();

      // 負數臨時 id（W1–W2：離線新增用，Issue #6 pull 後覆蓋為後端真實 id）
      final localId = SyncProvider.nextLocalId();

      final name = _nameCtrl.text.trim();
      final contact =
          _contactCtrl.text.trim().isEmpty ? null : _contactCtrl.text.trim();
      final taxId =
          _taxIdCtrl.text.trim().isEmpty ? null : _taxIdCtrl.text.trim();

      // Step 1：寫入本地 Drift
      await db.insertCustomer(
        CustomersCompanion(
          id: Value(localId),
          name: Value(name),
          contact: Value(contact),
          taxId: Value(taxId),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      // Step 2：排入同步佇列（payload 為完整 entity 快照）
      await sync.enqueueCreate('customer', {
        'id': localId,
        'name': name,
        'contact': contact,
        'taxId': taxId,
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'deletedAt': null,
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('儲存失敗：$e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('新增客戶'),
        actions: [
          if (!_saving)
            TextButton(
              onPressed: _save,
              child: const Text('儲存'),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            // 說明卡片
            Card(
              color: colorScheme.primaryContainer.withOpacity(0.4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '離線時可直接儲存，連線後自動同步至伺服器。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 客戶名稱（必填）
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '客戶名稱 *',
                hintText: '例：台灣科技股份有限公司',
                prefixIcon: Icon(Icons.business_outlined),
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? '請輸入客戶名稱' : null,
            ),
            const SizedBox(height: 16),

            // 聯絡人（選填）
            TextFormField(
              controller: _contactCtrl,
              decoration: const InputDecoration(
                labelText: '聯絡人',
                hintText: '例：王大明',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),

            // 統一編號（選填，8 位數字）
            TextFormField(
              controller: _taxIdCtrl,
              decoration: const InputDecoration(
                labelText: '統一編號',
                hintText: '8 位數字（選填）',
                prefixIcon: Icon(Icons.tag_outlined),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              maxLength: 8,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                if (!RegExp(r'^\d{8}$').hasMatch(v.trim())) {
                  return '統一編號須為 8 位數字';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // 儲存按鈕
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? '儲存中...' : '儲存客戶'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
