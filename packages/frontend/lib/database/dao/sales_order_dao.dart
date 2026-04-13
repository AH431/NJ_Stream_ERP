// ==============================================================================
// SalesOrderDao — AppDatabase extension（Issue #9 擴充）
//
// Issue #8 最小範疇：insertSalesOrder + upsertSalesOrderFromServer
// Issue #9 補充：
//   3. watchActiveSalesOrders — 供 SalesOrderListScreen 監聽
//   4. updateSalesOrderStatus — 樂觀更新訂單狀態（確認 / 取消）
// ==============================================================================

import 'package:drift/drift.dart';
import '../database.dart';

extension SalesOrderDao on AppDatabase {
  // --------------------------------------------------------------------------
  // Read
  // --------------------------------------------------------------------------

  /// 監聽所有未軟刪除的銷售訂單（供 SalesOrderListScreen 使用）
  /// 依 updatedAt 降序（最近異動的排前面）
  Stream<List<SalesOrder>> watchActiveSalesOrders() {
    return (select(salesOrders)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .watch();
  }

  // --------------------------------------------------------------------------
  // Write
  // --------------------------------------------------------------------------

  /// 插入新銷售訂單（離線轉訂單時 id 為負數臨時 id）
  Future<void> insertSalesOrder(SalesOrdersCompanion companion) async {
    await into(salesOrders).insert(companion);
  }

  /// 樂觀更新訂單狀態（確認 / 取消）
  /// [confirmedAt]：確認訂單時傳入；取消時傳 null
  /// [shippedAt]：出貨時傳入；其餘情境傳 null
  Future<void> updateSalesOrderStatus(
    int id,
    String status, {
    DateTime? confirmedAt,
    DateTime? shippedAt,
  }) async {
    final now = DateTime.now().toUtc();
    await (update(salesOrders)..where((t) => t.id.equals(id))).write(
      SalesOrdersCompanion(
        status: Value(status),
        confirmedAt: Value(confirmedAt),
        shippedAt: Value(shippedAt),
        updatedAt: Value(now),
      ),
    );
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
