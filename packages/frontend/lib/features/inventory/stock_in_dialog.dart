// ==============================================================================
// StockInDialog — 入庫對話框（Issue #11）
//
// 功能：
//   warehouse / admin 選擇產品與數量後排入入庫操作（inventory_delta type: in）
//
// 設計說明：
//   - 不做本地樂觀更新：inventory_items 由後端透過 DELTA_UPDATE 更新，
//     前端只 enqueue，等 Pull 後才更新畫面，避免顯示未確認庫存數字。
//   - 產品下拉只顯示本地有對應 inventory_items 記錄的產品，
//     防止選到無庫存記錄的產品導致後端回 DATA_CONFLICT。
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../database/database.dart';
import '../../database/dao/inventory_items_dao.dart';
import '../../database/dao/product_dao.dart';
import '../../providers/sync_provider.dart';

class StockInDialog extends StatefulWidget {
  const StockInDialog({super.key});

  @override
  State<StockInDialog> createState() => _StockInDialogState();
}

class _StockInDialogState extends State<StockInDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();

  int? _selectedProductId;
  List<Product> _eligibleProducts = [];
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadEligibleProducts();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  // 只顯示本地有 inventory_items 記錄的產品
  Future<void> _loadEligibleProducts() async {
    final db = context.read<AppDatabase>();

    final invItems  = await db.watchInventoryItems().first;
    final validIds  = invItems.map((i) => i.productId).toSet();
    final allProducts = await db.getActiveProducts();

    if (mounted) {
      setState(() {
        _eligibleProducts = allProducts.where((p) => validIds.contains(p.id)).toList();
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    final sync = context.read<SyncProvider>();

    await sync.enqueueDeltaUpdate('inventory_delta', 'in', {
      'productId': _selectedProductId,
      'amount': int.parse(_amountController.text.trim()),
    });

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return AlertDialog(
      title: Text(s.stockInTitle),
      content: _loading
          ? const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            )
          : _eligibleProducts.isEmpty
              ? Text(s.stockInNoProducts)
              : Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 產品選擇
                      DropdownButtonFormField<int>(
                        value: _selectedProductId,
                        decoration: InputDecoration(labelText: s.stockInFieldProd),
                        items: _eligibleProducts
                            .map((p) => DropdownMenuItem(
                                  value: p.id,
                                  child: Text('${p.name}（${p.sku}）',
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedProductId = v),
                        validator: (v) => v == null ? s.isEnglish ? 'Please select a product.' : '請選擇產品' : null,
                      ),
                      const SizedBox(height: 12),
                      // 入庫數量
                      TextFormField(
                        controller: _amountController,
                        decoration: InputDecoration(
                          labelText: s.stockInFieldQty,
                          hintText: s.isEnglish ? 'Enter a positive integer' : '請輸入正整數',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return s.stockInErrQty;
                          final n = int.tryParse(v.trim());
                          if (n == null || n <= 0) return s.stockInErrQty;
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context, false),
          child: Text(s.btnCancel),
        ),
        if (!_loading && _eligibleProducts.isNotEmpty)
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(s.btnSubmitStockIn),
          ),
      ],
    );
  }
}
