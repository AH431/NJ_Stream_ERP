// ==============================================================================
// ReserveInventoryDialog — 預留庫存確認（Issue #12）
//
// 職責：
//   顯示報價明細 + 本地庫存快照，讓業務確認後才 enqueue reserve。
//   警示邏輯：available < qty → ⚠️ 橘色列（不阻擋，服務端 INSUFFICIENT_STOCK 兜底）
// ==============================================================================

import 'package:flutter/material.dart';

import '../../database/database.dart';
import '../../database/dao/quotation_dao.dart';

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
    final hasWarning = items.any((item) {
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
            if (hasWarning) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.warning_amber_outlined,
                      size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '部分商品本地庫存可能不足，建議先同步後再執行。',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
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
