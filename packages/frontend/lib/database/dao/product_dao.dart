// ==============================================================================
// ProductDao — AppDatabase extension
//
// 設計說明：同 CustomerDao，使用 extension 而非 @DriftAccessor。
//
// 產品管理權限（PRD v0.8 §3）：
//   - 讀取：全角色
//   - 寫入（新增/刪除）：僅 admin
// ==============================================================================

import 'package:drift/drift.dart';

import '../database.dart';
import '../schema.dart';

extension ProductDao on AppDatabase {
  // --------------------------------------------------------------------------
  // Read
  // --------------------------------------------------------------------------

  /// 監聽未軟刪除的產品清單，依名稱升序排列。
  Stream<List<Product>> watchActiveProducts() {
    return (select(products)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  /// 一次性查詢
  Future<List<Product>> getActiveProducts() {
    return (select(products)..where((t) => t.deletedAt.isNull())).get();
  }

  // --------------------------------------------------------------------------
  // Write
  // --------------------------------------------------------------------------

  /// 插入新產品（id 為負數臨時 id，同步後由 Issue #6 pull 覆蓋）
  Future<void> insertProduct(ProductsCompanion companion) async {
    await into(products).insert(companion);
  }

  /// 軟刪除：設定 deleted_at + updatedAt
  Future<void> softDeleteProduct(int id, DateTime deletedAt) async {
    await (update(products)..where((t) => t.id.equals(id))).write(
      ProductsCompanion(
        deletedAt: Value<DateTime?>(deletedAt),
        updatedAt: Value(deletedAt),
      ),
    );
  }

  /// 從伺服器 upsert（Issue #6 pull 機制使用）
  Future<void> upsertProductFromServer(ProductsCompanion companion) async {
    await into(products).insertOnConflictUpdate(companion);
  }
}
