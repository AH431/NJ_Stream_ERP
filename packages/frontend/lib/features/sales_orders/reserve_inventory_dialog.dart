// ==============================================================================
// ReserveInventoryDialog — 預留庫存確認（Issue #12）
//
// 回傳值 ReserveDialogAction：
//   confirmed   — 庫存充足，使用者確認預留
//   waitForStock — 庫存不足，使用者選擇等待到貨
//   splitOrder  — 庫存不足，使用者選擇拆單
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../database/database.dart';
import '../../database/dao/quotation_dao.dart';

enum ReserveDialogAction { confirmed, waitForStock, splitOrder }

class ReserveInventoryDialog extends StatelessWidget {
  final SalesOrder order;
  final List<QuotationItemModel> items;
  final Map<int, Product> productMap;
  final Map<int, InventoryItem> inventoryMap;

  const ReserveInventoryDialog({
    super.key,
    required this.order,
    required this.items,
    required this.productMap,
    required this.inventoryMap,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppStrings>();
    // 任一品項可出貨數 < 預留需求 → 顯示警示並封鎖確認按鈕
    final hasInsufficient = items.any((item) {
      final inv = inventoryMap[item.productId];
      if (inv == null) return false;
      return (inv.quantityOnHand - inv.quantityReserved) < item.quantity;
    });

    return AlertDialog(
      title: Text(s.reserveTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.reserveWarning,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
            if (hasInsufficient) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.block, size: 16, color: Colors.red.shade700),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      s.reserveInsuffMsg,
                      style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              itemBuilder: (_, i) => _buildItemRow(items[i], s),
            ),
          ],
        ),
      ),
      actions: hasInsufficient
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: Text(s.btnCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, ReserveDialogAction.waitForStock),
                child: Text(s.btnWaitForStock),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, ReserveDialogAction.splitOrder),
                style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                child: Text(s.btnSplitOrder),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: Text(s.btnCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, ReserveDialogAction.confirmed),
                child: Text(s.btnConfirmReserve),
              ),
            ],
    );
  }

  Widget _buildItemRow(QuotationItemModel item, AppStrings s) {
    final product  = productMap[item.productId];
    final inv      = inventoryMap[item.productId];
    final available = inv != null
        ? inv.quantityOnHand - inv.quantityReserved
        : null;
    final isWarning = available != null && available < item.quantity;

    return Container(
      color: isWarning ? Colors.orange.shade50 : null,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 產品名稱 + SKU
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product?.name ?? (s.isEnglish ? 'Product #${item.productId}' : '產品 #${item.productId}'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                if (product != null)
                  Text(
                    product.sku,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
              ],
            ),
          ),
          // 預留數量
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                s.reserveQty(item.quantity),
                style: const TextStyle(
                    fontSize: 13, color: Colors.indigo, fontWeight: FontWeight.w600),
              ),
              Text(
                available != null
                    ? s.reserveAvailable(available)
                    : s.reserveNoRecord,
                style: TextStyle(
                  fontSize: 11,
                  color: isWarning
                      ? Colors.orange.shade700
                      : Colors.green.shade700,
                ),
              ),
            ],
          ),
          if (isWarning) ...[
            const SizedBox(width: 4),
            Icon(Icons.warning_amber_outlined,
                size: 14, color: Colors.orange.shade700),
          ],
        ],
      ),
    );
  }
}
