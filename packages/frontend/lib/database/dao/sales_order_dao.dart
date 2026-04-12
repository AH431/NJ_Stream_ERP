// ==============================================================================
// SalesOrderDao — AppDatabase extension（最小範疇，Issue #8）
//
// 本 Issue 只需支援：
//   1. 轉訂單時本地 insert（樂觀寫入，id 為負數）
//   2. Pull / Force Overwrite 時 upsert 伺服器狀態
// 銷售訂單列表 UI 留後續 Issue 實作。
// ==============================================================================

import '../database.dart';

extension SalesOrderDao on AppDatabase {
  // --------------------------------------------------------------------------
  // Write
  // --------------------------------------------------------------------------

  /// 插入新銷售訂單（離線轉訂單時 id 為負數臨時 id）
  Future<void> insertSalesOrder(SalesOrdersCompanion companion) async {
    await into(salesOrders).insert(companion);
  }

  /// 從伺服器 upsert（pull / Force Overwrite 使用）
  /// LWW：若本地 updatedAt 較新或相同，不覆蓋
  Future<void> upsertSalesOrderFromServer(
      SalesOrdersCompanion companion) async {
    return transaction(() async {
      final serverId        = companion.id.value;
      final serverUpdatedAt = companion.updatedAt.value;

      final existing = await (select(salesOrders)
            ..where((t) => t.id.equals(serverId)))
          .getSingleOrNull();

      if (existing != null) {
        if (existing.updatedAt.isAfter(serverUpdatedAt) ||
            existing.updatedAt.isAtSameMomentAs(serverUpdatedAt)) {
          return;
        }
      }

      await into(salesOrders).insertOnConflictUpdate(companion);
    });
  }
}
