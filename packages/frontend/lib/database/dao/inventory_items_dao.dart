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

extension InventoryItemsDao on AppDatabase {
  // --------------------------------------------------------------------------
  // Read
  // --------------------------------------------------------------------------

  /// 監聽所有庫存快照（供庫存列表 UI 使用）
  /// 依 productId 升序排列，便於搭配產品列表對照
  Stream<List<InventoryItem>> watchInventoryItems() {
    return (select(inventoryItems)
          ..orderBy([(t) => OrderingTerm.asc(t.productId)]))
        .watch();
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
