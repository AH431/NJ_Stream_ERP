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

  /// 監聽待出貨訂單數（status = confirmed，供 Dashboard 使用）
  Stream<int> watchConfirmedOrderCount() {
    final countExp = salesOrders.id.count();
    return (selectOnly(salesOrders)
          ..addColumns([countExp])
          ..where(salesOrders.status.equals('confirmed') &
              salesOrders.deletedAt.isNull()))
        .watchSingle()
        .map((row) => row.read(countExp) ?? 0);
  }

  /// 取得客戶最近 N 筆未軟刪除訂單（供 CustomerDetailScreen 使用）
  Future<List<SalesOrder>> getRecentOrdersForCustomer(
    int customerId, {
    int limit = 5,
  }) =>
      (select(salesOrders)
            ..where((t) =>
                t.customerId.equals(customerId) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
            ..limit(limit))
          .get();

  /// 監聽所有未軟刪除的銷售訂單（供 SalesOrderListScreen 使用）。
  /// 排序：流程進度（待處理 → 確認未預留 → 確認已預留 → 出貨 → 取消），同狀態內 createdAt 降序（最新在上）
  Stream<List<SalesOrder>> watchActiveSalesOrders() {
    return (select(salesOrders)
          ..where((t) => t.deletedAt.isNull()))
        .watch()
        .map((list) {
          list.sort((a, b) {
            final pa = _orderPriority(a);
            final pb = _orderPriority(b);
            if (pa != pb) return pa.compareTo(pb);
            return b.createdAt.compareTo(a.createdAt);
          });
          return list;
        });
  }

  int _orderPriority(SalesOrder o) {
    if (o.status == 'pending') return 0;
    if (o.status == 'confirmed' && o.reservedAt == null) return 1;
    if (o.status == 'confirmed' && o.reservedAt != null) return 2;
    if (o.status == 'shipped') return 3;
    if (o.status == 'cancelled') return 4;
    return 9;
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
  /// [shippedAt]：出貨時傳入；其餘情境不傳（保留現有值）
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
        // Value.absent() = 不更新該欄位，保留 DB 現有值（審計記錄不得清除）
        confirmedAt: confirmedAt != null ? Value(confirmedAt) : const Value.absent(),
        shippedAt:   shippedAt   != null ? Value(shippedAt)   : const Value.absent(),
        updatedAt: Value(now),
      ),
    );
  }

  /// 標記庫存已預留（本地端，控制「出貨」按鈕可見性），同時清除警示標記
  Future<void> markSalesOrderReserved(int id) async {
    final now = DateTime.now().toUtc();
    await (update(salesOrders)..where((t) => t.id.equals(id))).write(
      SalesOrdersCompanion(
        reservedAt: Value(now),
        stockAlertAt: const Value(null), // 預留成功，清除庫存不足警示
      ),
    );
  }

  /// 清除庫存預留標記（INSUFFICIENT_STOCK 409 時回滾，重新鎖定「出貨」按鈕）
  Future<void> clearSalesOrderReserved(int id) async {
    await (update(salesOrders)..where((t) => t.id.equals(id))).write(
      const SalesOrdersCompanion(reservedAt: Value(null)),
    );
  }

  /// 標記庫存不足警示（本地端，顯示橘色「庫存不足」按鈕）
  Future<void> markSalesOrderStockAlert(int id) async {
    final now = DateTime.now().toUtc();
    await (update(salesOrders)..where((t) => t.id.equals(id))).write(
      SalesOrdersCompanion(stockAlertAt: Value(now)),
    );
  }

  /// 清除庫存不足警示（訂單取消或庫存補足後呼叫）
  Future<void> clearSalesOrderStockAlert(int id) async {
    await (update(salesOrders)..where((t) => t.id.equals(id))).write(
      const SalesOrdersCompanion(stockAlertAt: Value(null)),
    );
  }

  /// 軟刪除銷售訂單
  /// 設定 deletedAt，讓 watchActiveSalesOrders 自動過濾掉殘留記錄
  Future<void> softDeleteSalesOrder(int id, DateTime deletedAt) async {
    await (update(salesOrders)..where((t) => t.id.equals(id))).write(
      SalesOrdersCompanion(
        deletedAt: Value(deletedAt),
        updatedAt: Value(deletedAt),
      ),
    );
  }

  /// 軟刪除本地臨時訂單（push 被伺服器拒絕時回滾用）
  Future<void> softDeleteLocalSalesOrder(int localId) async {
    final now = DateTime.now().toUtc();
    await softDeleteSalesOrder(localId, now);
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
