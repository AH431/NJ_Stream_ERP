// ==============================================================================
// ShipOrderDialog — 出貨庫存預覽確認（Issue #13）
//
// 職責：
//   顯示出貨明細 + 本地庫存快照，同時呈現 onHand 與 reserved 的扣減預覽。
//   警示 A：reservedQty < shippingQty → 尚未預留，服務端將拒絕（INSUFFICIENT_STOCK）
//   警示 B：onHandQty  < shippingQty → 在庫不足
//   兩者皆不阻擋操作，服務端 409 + Force Pull 為最終兜底。
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../database/database.dart';
import '../../database/dao/quotation_dao.dart';

class ShipOrderDialog extends StatelessWidget {
  final SalesOrder order;
  final List<QuotationItemModel> items;
  final Map<int, Product> productMap;
  final Map<int, InventoryItem> inventoryMap;

  const ShipOrderDialog({
    super.key,
    required this.order,
    required this.items,
    required this.productMap,
    required this.inventoryMap,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppStrings>();
    final hasNotReserved = items.any((item) {
      final inv = inventoryMap[item.productId];
      return inv != null && inv.quantityReserved < item.quantity;
    });
    final hasInsufficient = items.any((item) {
      final inv = inventoryMap[item.productId];
      return inv != null && inv.quantityOnHand < item.quantity;
    });

    return AlertDialog(
      title: Text(s.shipTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.shipWarningBody,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
            if (hasNotReserved) ...[
              const SizedBox(height: 8),
              _buildBanner(
                icon: Icons.warning_amber_outlined,
                color: Colors.orange,
                text: s.shipBannerNoReserve,
              ),
            ],
            if (hasInsufficient) ...[
              const SizedBox(height: 6),
              _buildBanner(
                icon: Icons.error_outline,
                color: Colors.red,
                text: s.shipBannerInsufficient,
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(s.btnCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.green),
          onPressed: () => Navigator.pop(context, true),
          child: Text(s.btnConfirmShip),
        ),
      ],
    );
  }

  Widget _buildBanner({
    required IconData icon,
    required MaterialColor color,
    required String text,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color.shade700),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: color.shade700),
          ),
        ),
      ],
    );
  }

  Widget _buildItemRow(QuotationItemModel item, AppStrings s) {
    final product  = productMap[item.productId];
    final inv      = inventoryMap[item.productId];

    final postOnHand   = inv != null ? inv.quantityOnHand   - item.quantity : null;
    final postReserved = inv != null ? inv.quantityReserved - item.quantity : null;

    final isNotReserved  = inv != null && inv.quantityReserved < item.quantity;
    final isInsufficient = inv != null && inv.quantityOnHand   < item.quantity;

    Color rowColor = Colors.transparent;
    if (isInsufficient) {
      rowColor = Colors.red.shade50;
    } else if (isNotReserved) {
      rowColor = Colors.orange.shade50;
    }

    final onHandLabel    = s.isEnglish ? 'On Hand' : '在庫';
    final reservedLabel  = s.isEnglish ? 'Reserved' : '預留';

    return Container(
      color: rowColor,
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
          // 出貨數量 + 出貨後 onHand / reserved
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                s.shipQty(item.quantity),
                style: const TextStyle(
                    fontSize: 13,
                    color: Colors.indigo,
                    fontWeight: FontWeight.w600),
              ),
              if (inv != null) ...[
                Text(
                  '$onHandLabel ${inv.quantityOnHand} → ${postOnHand! < 0 ? '⚠ $postOnHand' : '$postOnHand'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isInsufficient ? Colors.red.shade700 : Colors.green.shade700,
                  ),
                ),
                Text(
                  '$reservedLabel ${inv.quantityReserved} → ${postReserved! < 0 ? '⚠ $postReserved' : '$postReserved'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isNotReserved ? Colors.orange.shade700 : Colors.grey.shade600,
                  ),
                ),
              ] else
                Text(
                  s.shipNoRecord,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
            ],
          ),
          // 警示 icon
          if (isInsufficient || isNotReserved) ...[
            const SizedBox(width: 4),
            Icon(
              isInsufficient ? Icons.error_outline : Icons.warning_amber_outlined,
              size: 14,
              color: isInsufficient ? Colors.red.shade700 : Colors.orange.shade700,
            ),
          ],
        ],
      ),
    );
  }
}
