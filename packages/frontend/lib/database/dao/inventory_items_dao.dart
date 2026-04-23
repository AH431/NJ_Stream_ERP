// ==============================================================================
// InventoryItemsDao — AppDatabase extension（Issue #9）
//
// 職責：
//   1. 監聽庫存快照（watchInventoryItems — 供庫存列表 UI 使用）
//   2. 依 productId 查詢單筆（getInventoryItemByProductId — 供確認訂單 reserve 使用）
//   3. 從伺服器 upsert（Pull / Force Overwrite，LWW 以 updatedAt 判斷）
//
// 設計說明：
//   InventoryItem 不可由前端直接修改，只能透過 DELTA_UPDATE 操作（後端寫入後 Pull 下來）。
//   upsertInventoryItemFromServer 是前端唯一的寫入路徑。
// ==============================================================================

import 'package:drift/drift.dart';
import '../database.dart';

/// 低庫存快照（Dashboard 用）
/// available = onHand - reserved
class LowStockItem {
  final int productId;
  final String productName;
  final String sku;
  final int onHand;
  final int reserved;
  final int minStockLevel;

  const LowStockItem({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.onHand,
    required this.reserved,
    required this.minStockLevel,
  });

  int get available => onHand - reserved;
}

extension InventoryItemsDao on AppDatabase {
  // --------------------------------------------------------------------------
  // Read
  // --------------------------------------------------------------------------

  /// 監聽低庫存品項（供 Dashboard 使用）
  /// 條件：minStockLevel > 0 且 (onHand - reserved) <= minStockLevel
  /// 以 JOIN products 取得產品名稱與 SKU，在 Dart 層套用可出貨量過濾
  Stream<List<LowStockItem>> watchLowStockItems() {
    final query = select(inventoryItems).join([
      innerJoin(products, products.id.equalsExp(inventoryItems.productId)),
    ])
      ..where(products.minStockLevel.isBiggerThanValue(0)) // 改用產品主檔的設定
      ..where(products.deletedAt.isNull())
      ..orderBy([OrderingTerm.asc(inventoryItems.productId)]);

    return query.watch().map((rows) {
      return rows
          .map((row) {
            final inv = row.readTable(inventoryItems);
            final prd = row.readTable(products);
            return LowStockItem(
              productId: inv.productId,
              productName: prd.name,
              sku: prd.sku,
              onHand: inv.quantityOnHand,
              reserved: inv.quantityReserved,
              minStockLevel: prd.minStockLevel, // 改用產品主檔的設定
            );
          })
          .where((item) => item.available <= item.minStockLevel)
          .toList();
    });
  }

  /// 監聽所有庫存快照（供庫存列表 UI 使用）
  /// INNER JOIN Products：自動過濾已軟刪除產品的殘存庫存記錄
  /// 依 productId 升序排列
  Stream<List<InventoryItem>> watchInventoryItems() {
    final query = select(inventoryItems).join([
      innerJoin(products, products.id.equalsExp(inventoryItems.productId)),
    ])
      ..where(products.deletedAt.isNull())
      ..orderBy([OrderingTerm.asc(inventoryItems.productId)]);
    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(inventoryItems)).toList(),
    );
  }

  /// 從本地 DB 實體刪除指定庫存記錄（Admin 手動清理孤立記錄用）
  /// 注意：不進同步佇列，Pull 後若後端仍存在則會由 upsert 恢復
  Future<void> deleteInventoryItem(int id) async {
    await (delete(inventoryItems)..where((t) => t.id.equals(id))).go();
  }

  /// 依 productId 查詢單筆庫存（供確認訂單計算 reserve 使用）
  Future<InventoryItem?> getInventoryItemByProductId(int productId) {
    return (select(inventoryItems)
          ..where((t) => t.productId.equals(productId)))
        .getSingleOrNull();
  }

  // --------------------------------------------------------------------------
  // Write
  // --------------------------------------------------------------------------

  /// 從伺服器 upsert（Pull / Force Overwrite 使用）
  /// LWW：若本地 updatedAt 較新或相同，不覆蓋
  Future<void> upsertInventoryItemFromServer(
      InventoryItemsCompanion companion) async {
    return transaction(() async {
      final serverId = companion.id.value;
      final serverUpdatedAt = companion.updatedAt.value;

      final existing = await (select(inventoryItems)
            ..where((t) => t.id.equals(serverId)))
          .getSingleOrNull();

      if (existing != null) {
        if (existing.updatedAt.isAfter(serverUpdatedAt) ||
            existing.updatedAt.isAtSameMomentAs(serverUpdatedAt)) {
          return;
        }
      }

      await into(inventoryItems).insertOnConflictUpdate(companion);
    });
  }
}
