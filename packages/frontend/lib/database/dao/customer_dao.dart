// ==============================================================================
// CustomerDao — AppDatabase extension
//
// 設計說明：
//   使用 Dart extension 而非 @DriftAccessor，避免重新執行 build_runner codegen。
//   所有對 customers 表的 DB 操作集中於此，feature layer 不直接拼 Drift query。
//
// 軟刪除規則（同步協定 v1.6 + api-contract-sync-v1.6.yaml）：
//   刪除一律寫入 deleted_at，嚴禁 Hard Delete。
//   PendingOperations 使用 operationType: 'delete'（非 'update'）。
// ==============================================================================

import 'package:drift/drift.dart';

import '../database.dart';

extension CustomerDao on AppDatabase {
  // --------------------------------------------------------------------------
  // Read
  // --------------------------------------------------------------------------

  /// 監聽未軟刪除的客戶清單（deleted_at IS NULL），依 updatedAt 降序排列。
  /// 回傳 Stream，SearchBuilder 可即時響應變更。
  Stream<List<Customer>> watchActiveCustomers() {
    return (select(customers)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  /// 一次性查詢（用於非 UI 場景）
  Future<List<Customer>> getActiveCustomers() {
    return (select(customers)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  // --------------------------------------------------------------------------
  // Write
  // --------------------------------------------------------------------------

  /// 插入新客戶（離線新增時 id 為負數臨時 id，同步後由 Issue #6 pull 覆蓋）
  Future<void> insertCustomer(CustomersCompanion companion) async {
    await into(customers).insert(companion);
  }

  /// 更新客戶資料
  Future<void> updateCustomer(int id, CustomersCompanion companion) async {
    await (update(customers)..where((t) => t.id.equals(id))).write(companion);
  }

  /// 軟刪除：寫入 deleted_at + 更新 updatedAt，不做 Hard Delete
  Future<void> softDeleteCustomer(int id, DateTime deletedAt) async {
    await (update(customers)..where((t) => t.id.equals(id))).write(
      CustomersCompanion(
        deletedAt: Value<DateTime?>(deletedAt),
        updatedAt: Value(deletedAt),
      ),
    );
  }

  /// 從伺服器 upsert（Issue #6 pull 機制使用）
  /// 實作 LWW (Last-Write-Wins)：若本地紀錄較新則放棄覆蓋
  Future<void> upsertCustomerFromServer(CustomersCompanion companion) async {
    return transaction(() async {
      final serverId = companion.id.value;
      final serverUpdatedAt = companion.updatedAt.value;

      final existing = await (select(customers)
            ..where((t) => t.id.equals(serverId)))
          .getSingleOrNull();

      if (existing != null) {
        if (existing.updatedAt.isAfter(serverUpdatedAt) || 
            existing.updatedAt.isAtSameMomentAs(serverUpdatedAt)) {
          // 本地較新或相同，不覆蓋
          return;
        }
      }

      await into(customers).insertOnConflictUpdate(companion);
    });
  }

  /// 清除無對應 PendingOperation 的本地臨時客戶資料 (id < 0)
  /// 解決 Pull 時產生的雙胞胎問題
  Future<void> clearOrphanedOfflineCustomers(List<String> pendingRelatedIds) async {
    await (delete(customers)
          ..where((t) => t.id.isBiggerOrEqualValue(0).not())
          ..where((t) => t.id.cast<String>().isIn(
                pendingRelatedIds.map((idStr) => idStr.split(':').last)
              ).not()))
        .go();
  }

  /// 硬刪除本地所有客戶記錄（開發偵錯用，不影響後端）
  Future<void> hardDeleteAllLocalCustomers() async {
    await delete(customers).go();
  }
}
