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
import '../schema.dart';

extension CustomerDao on AppDatabase {
  // --------------------------------------------------------------------------
  // Read
  // --------------------------------------------------------------------------

  /// 監聽未軟刪除的客戶清單（deleted_at IS NULL），依 updatedAt 降序排列。
  /// 回傳 Stream，SearchBuilder 可即時響應變更。
  Stream<List<Customer>> watchActiveCustomers() {
    return (select(customers)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .watch();
  }

  /// 一次性查詢（用於非 UI 場景）
  Future<List<Customer>> getActiveCustomers() {
    return (select(customers)..where((t) => t.deletedAt.isNull())).get();
  }

  // --------------------------------------------------------------------------
  // Write
  // --------------------------------------------------------------------------

  /// 插入新客戶（離線新增時 id 為負數臨時 id，同步後由 Issue #6 pull 覆蓋）
  Future<void> insertCustomer(CustomersCompanion companion) async {
    await into(customers).insert(companion);
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
  /// 以 id 衝突時更新所有欄位（覆蓋本地負數臨時 id 記錄）
  Future<void> upsertCustomerFromServer(CustomersCompanion companion) async {
    await into(customers).insertOnConflictUpdate(companion);
  }
}
