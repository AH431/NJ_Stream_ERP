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

import '../../core/app_strings.dart';
import '../../database/dao/customer_dao.dart';
import '../../database/database.dart';
import '../../providers/sync_provider.dart';

class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({super.key});

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl    = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _taxIdCtrl   = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _emailCtrl.dispose();
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
      final db   = context.read<AppDatabase>();
      final sync = context.read<SyncProvider>();
      final s    = context.read<AppStrings>();
      final now  = DateTime.now().toUtc();

      // 負數臨時 id（W1–W2：離線新增用，Issue #6 pull 後覆蓋為後端真實 id）
      final localId = SyncProvider.nextLocalId();

      final name    = _nameCtrl.text.trim();
      final contact = _contactCtrl.text.trim().isEmpty ? null : _contactCtrl.text.trim();
      final email   = _emailCtrl.text.trim().isEmpty   ? null : _emailCtrl.text.trim();
      final taxId   = _taxIdCtrl.text.trim().isEmpty   ? null : _taxIdCtrl.text.trim();

      // Step 1：寫入本地 Drift
      await db.insertCustomer(
        CustomersCompanion(
          id:        Value(localId),
          name:      Value(name),
          contact:   Value(contact),
          email:     Value(email),
          taxId:     Value(taxId),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      // Step 2：排入同步佇列（payload 為完整 entity 快照）
      await sync.enqueueCreate('customer', {
        'id':        localId,
        'name':      name,
        'contact':   contact,
        'email':     email,
        'taxId':     taxId,
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
            content: Text(s.isEnglish ? 'Save failed: $e' : '儲存失敗：$e'),
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
    final s           = AppStrings.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.custFormTitle),
        actions: [
          if (!_saving)
            TextButton(
              onPressed: _save,
              child: Text(s.btnSave),
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
              color: colorScheme.primaryContainer.withValues(alpha: 0.4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.custOfflineNote,
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
              decoration: InputDecoration(
                labelText: s.custFieldName,
                hintText: s.isEnglish ? 'e.g. Acme Corp' : '例：台灣科技股份有限公司',
                prefixIcon: const Icon(Icons.business_outlined),
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? s.errNameRequired : null,
            ),
            const SizedBox(height: 16),

            // 聯絡人（選填）
            TextFormField(
              controller: _contactCtrl,
              decoration: InputDecoration(
                labelText: s.custFieldContact,
                hintText: s.isEnglish ? 'e.g. John Smith' : '例：王大明',
                prefixIcon: const Icon(Icons.person_outline),
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),

            // Email（選填，用於寄送報價單/訂單/對帳單）
            TextFormField(
              controller: _emailCtrl,
              decoration: InputDecoration(
                labelText: s.custFieldEmail,
                hintText: 'e.g. contact@company.com',
                prefixIcon: const Icon(Icons.email_outlined),
                border: const OutlineInputBorder(),
                helperText: s.custEmailHelper,
              ),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
                  return s.errEmailInvalid;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 統一編號（選填，8 位數字）
            TextFormField(
              controller: _taxIdCtrl,
              decoration: InputDecoration(
                labelText: s.custFieldTaxId,
                hintText: s.isEnglish ? '8 digits (optional)' : '8 位數字（選填）',
                prefixIcon: const Icon(Icons.tag_outlined),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              maxLength: 8,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                if (!RegExp(r'^\d{8}$').hasMatch(v.trim())) {
                  return s.errTaxIdInvalid;
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
              label: Text(_saving ? s.btnSaving : s.btnSaveCustomer),
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
