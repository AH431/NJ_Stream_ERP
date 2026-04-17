// ==============================================================================
// ReserveInventoryDialog — 預留庫存確認（Issue #12）
//
// 回傳值 ReserveDialogAction：
//   confirmed   — 庫存充足，使用者確認預留
//   waitForStock — 庫存不足，使用者選擇等待到貨
//   splitOrder  — 庫存不足，使用者選擇拆單
// ==============================================================================

import 'package:flutter/material.dart';

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
    // 任一品項可出貨數 < 預留需求 → 顯示警示並封鎖確認按鈕
    final hasInsufficient = items.any((item) {
      final inv = inventoryMap[item.productId];
      if (inv == null) return false;
      return (inv.quantityOnHand - inv.quantityReserved) < item.quantity;
    });

    return AlertDialog(
      title: const Text('預留庫存確認'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '以下庫存將被預留，確認後不可撤回（需重新取消訂單才能釋放）。',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            if (hasInsufficient) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.block, size: 16, color: Colors.red.shade700),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '庫存不足，無法預留。請先同步最新庫存後再執行。',
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
              itemBuilder: (_, i) => _buildItemRow(items[i]),
            ),
          ],
        ),
      ),
      actions: hasInsufficient
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, ReserveDialogAction.waitForStock),
                child: const Text('等待到貨通知'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, ReserveDialogAction.splitOrder),
                style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text('請拆單'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, ReserveDialogAction.confirmed),
                child: const Text('確認預留'),
              ),
            ],
    );
  }

  Widget _buildItemRow(QuotationItemModel item) {
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
                  product?.name ?? '產品 #${item.productId}',
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
                '預留 ${item.quantity}',
                style: const TextStyle(
                    fontSize: 13, color: Colors.indigo, fontWeight: FontWeight.w600),
              ),
              Text(
                available != null
                    ? '可出貨 $available'
                    : '— 無本地記錄',
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
