// ==============================================================================
// RemapDao — 離線 ID 替換（Issue #34）
//
// 用途：
//   Push 成功後，後端配發正整數 server ID；前端需將本地負數臨時 ID
//   替換為 server ID，並更新所有相關外鍵與 pending_operations。
//
// 設計說明：
//   採用「先 insert with serverId（upsert），更新 FK，再 delete localId」順序，
//   避免 SQLite 外鍵約束問題（即使 SQLite 預設不啟用 FK，順序也更安全）。
// ==============================================================================

import 'package:drift/drift.dart';

import '../database.dart';

extension RemapDao on AppDatabase {
  // --------------------------------------------------------------------------
  // 對外入口：依 entityType 路由到對應的 remap 方法
  // --------------------------------------------------------------------------

  Future<void> remapEntityId(
      String entityType, int localId, int serverId) async {
    switch (entityType) {
      case 'customer':
        await _remapCustomer(localId, serverId);
      case 'quotation':
        await _remapQuotation(localId, serverId);
      case 'sales_order':
        await _remapSalesOrder(localId, serverId);
      case 'customer_interaction':
        await _remapCustomerInteraction(localId, serverId);
    }
  }

  // --------------------------------------------------------------------------
  // Customer：localId → serverId
  //   影響表：customers（主鍵）、quotations.customerId、salesOrders.customerId
  // --------------------------------------------------------------------------

  Future<void> _remapCustomer(int localId, int serverId) async {
    final existing = await (select(customers)
          ..where((t) => t.id.equals(localId)))
        .getSingleOrNull();
    if (existing == null) return;

    // 1. 以 serverId 插入（若 Pull 已帶回同 ID 則 upsert 更新）
    await into(customers)
        .insertOnConflictUpdate(existing.toCompanion(false).copyWith(
          id: Value(serverId),
        ));

    // 2. 更新相關外鍵
    await (update(quotations)..where((t) => t.customerId.equals(localId)))
        .write(QuotationsCompanion(customerId: Value(serverId)));
    await (update(salesOrders)..where((t) => t.customerId.equals(localId)))
        .write(SalesOrdersCompanion(customerId: Value(serverId)));

    // 3. 刪除舊的臨時 ID 記錄
    await (delete(customers)..where((t) => t.id.equals(localId))).go();
  }

  // --------------------------------------------------------------------------
  // Quotation：localId → serverId
  //   影響表：quotations（主鍵）、salesOrders.quotationId
  // --------------------------------------------------------------------------

  Future<void> _remapQuotation(int localId, int serverId) async {
    final existing = await (select(quotations)
          ..where((t) => t.id.equals(localId)))
        .getSingleOrNull();
    if (existing == null) return;

    await into(quotations)
        .insertOnConflictUpdate(existing.toCompanion(false).copyWith(
          id: Value(serverId),
        ));

    await (update(salesOrders)..where((t) => t.quotationId.equals(localId)))
        .write(SalesOrdersCompanion(quotationId: Value(serverId)));

    await (delete(quotations)..where((t) => t.id.equals(localId))).go();
  }

  // --------------------------------------------------------------------------
  // SalesOrder：localId → serverId
  //   影響表：salesOrders（主鍵）、orderItems.orderId
  // --------------------------------------------------------------------------

  Future<void> _remapSalesOrder(int localId, int serverId) async {
    final existing = await (select(salesOrders)
          ..where((t) => t.id.equals(localId)))
        .getSingleOrNull();
    if (existing == null) return;

    await into(salesOrders)
        .insertOnConflictUpdate(existing.toCompanion(false).copyWith(
          id: Value(serverId),
        ));

    await (update(orderItems)..where((t) => t.orderId.equals(localId)))
        .write(OrderItemsCompanion(orderId: Value(serverId)));

    await (delete(salesOrders)..where((t) => t.id.equals(localId))).go();
  }

  // --------------------------------------------------------------------------
  // CustomerInteraction：localId → serverId
  //   影響表：customerInteractions（主鍵）；無外鍵被其他表引用
  // --------------------------------------------------------------------------

  Future<void> _remapCustomerInteraction(int localId, int serverId) async {
    final existing = await (select(customerInteractions)
          ..where((t) => t.id.equals(localId)))
        .getSingleOrNull();
    if (existing == null) return;

    await into(customerInteractions)
        .insertOnConflictUpdate(existing.toCompanion(false).copyWith(
          id: Value(serverId),
        ));

    await (delete(customerInteractions)..where((t) => t.id.equals(localId))).go();
  }

  // --------------------------------------------------------------------------
  // 更新 pending_operations.relatedEntityId（e.g. "customer:-1" → "customer:5"）
  // --------------------------------------------------------------------------

  Future<void> updatePendingRelatedEntityId(
      String entityType, int localId, int serverId) async {
    await (update(pendingOperations)
          ..where((t) =>
              t.relatedEntityId.equals('$entityType:$localId')))
        .write(PendingOperationsCompanion(
      relatedEntityId: Value('$entityType:$serverId'),
    ));
  }
}
