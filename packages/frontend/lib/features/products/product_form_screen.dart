// ==============================================================================
// ProductFormScreen — 新增產品表單（admin only）
//
// 欄位：name, sku, unitPrice（Decimal，格式驗證）, minStockLevel
// 儲存：本地 Drift 寫入 + SyncProvider.enqueueCreate('product', payload)
// ==============================================================================

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/dao/product_dao.dart';
import '../../database/database.dart';
import '../../providers/sync_provider.dart';

class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _skuCtrl = TextEditingController();
  final _unitPriceCtrl = TextEditingController();
  final _minStockCtrl = TextEditingController(text: '0');
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _skuCtrl.dispose();
    _unitPriceCtrl.dispose();
    _minStockCtrl.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // 儲存
  // --------------------------------------------------------------------------

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final db = context.read<AppDatabase>();
      final sync = context.read<SyncProvider>();
      final now = DateTime.now().toUtc();
      final localId = SyncProvider.nextLocalId();

      final name = _nameCtrl.text.trim();
      final sku = _skuCtrl.text.trim();
      // unitPrice 已通過 validator 驗證，Decimal.parse 不會拋出例外
      // ProductsCompanion.unitPrice 為 Value<String>（Drift codegen 以 String 儲存）
      // 使用 Decimal 解析後再格式化為 "xxx.xx"，確保符合合約 pattern: ^\d+\.\d{2}$
      final unitPriceDecimal = Decimal.parse(_unitPriceCtrl.text.trim());
      final unitPriceStr = unitPriceDecimal.toStringAsFixed(2);
      final minStock = int.tryParse(_minStockCtrl.text.trim()) ?? 0;

      // Step 1：本地 Drift 寫入
      await db.insertProduct(
        ProductsCompanion(
          id: Value(localId),
          name: Value(name),
          sku: Value(sku),
          unitPrice: Value(unitPriceDecimal), 
          minStockLevel: Value(minStock),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      // Step 2：排入同步佇列
      // unitPrice 已是 "xxx.xx" 格式，符合 api-contract-sync-v1.6.yaml ProductPayload.unitPrice
      await sync.enqueueCreate('product', {
        'id': localId,
        'name': name,
        'sku': sku,
        'unitPrice': unitPriceStr,
        'minStockLevel': minStock,
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
        title: const Text('新增產品'),
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
              color: colorScheme.tertiaryContainer.withValues(alpha: 0.4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.admin_panel_settings_outlined,
                        size: 18, color: colorScheme.tertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '新增產品需 Admin 角色，離線時可儲存，連線後同步。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onTertiaryContainer,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 產品名稱（必填）
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '產品名稱 *',
                hintText: '例：高效能伺服器 Pro',
                prefixIcon: Icon(Icons.inventory_outlined),
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? '請輸入產品名稱' : null,
            ),
            const SizedBox(height: 16),

            // SKU（必填）
            TextFormField(
              controller: _skuCtrl,
              decoration: const InputDecoration(
                labelText: 'SKU *',
                hintText: '例：SVR-PRO-001',
                prefixIcon: Icon(Icons.qr_code_outlined),
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? '請輸入 SKU' : null,
            ),
            const SizedBox(height: 16),

            // 單價（必填，decimal 驗證，對應 api-contract ^\d+\.\d{2}$ 格式）
            TextFormField(
              controller: _unitPriceCtrl,
              decoration: InputDecoration(
                labelText: '單價 *',
                hintText: '例：158000.00',
                prefixIcon: const Icon(Icons.attach_money),
                prefixText: 'NT\$ ',
                border: const OutlineInputBorder(),
                helperText: '支援小數點後最多兩位',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '請輸入單價';
                // 允許整數或最多兩位小數
                if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(v.trim())) {
                  return '請輸入有效金額（最多兩位小數）';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 最低庫存警示（選填，預設 0）
            TextFormField(
              controller: _minStockCtrl,
              decoration: const InputDecoration(
                labelText: '最低庫存警示',
                hintText: '低於此數量時儀表板顯示警示',
                prefixIcon: Icon(Icons.warning_amber_outlined),
                border: OutlineInputBorder(),
                suffixText: '件',
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final n = int.tryParse(v.trim());
                if (n == null || n < 0) return '請輸入 0 以上的整數';
                return null;
              },
            ),
            const SizedBox(height: 32),

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
              label: Text(_saving ? '儲存中...' : '儲存產品'),
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
