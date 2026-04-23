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
    return (select(products)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
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
  /// 實作 LWW (Last-Write-Wins)：若本地紀錄較新則放棄覆蓋
  Future<void> upsertProductFromServer(ProductsCompanion companion) async {
    return transaction(() async {
      final serverId = companion.id.value;
      final serverUpdatedAt = companion.updatedAt.value;

      final existing = await (select(products)
            ..where((t) => t.id.equals(serverId)))
          .getSingleOrNull();

      if (existing != null) {
        if (existing.updatedAt.isAfter(serverUpdatedAt) || 
            existing.updatedAt.isAtSameMomentAs(serverUpdatedAt)) {
          // 本地較新或相同，不覆蓋
          return;
        }
      }

      await into(products).insertOnConflictUpdate(companion);
    });
  }

  /// 清除無對應 PendingOperation 的本地臨時產品資料 (id < 0)
  /// 解決 Pull 時產生的雙胞胎問題
  Future<void> clearOrphanedOfflineProducts(List<String> pendingRelatedIds) async {
    await (delete(products)
          ..where((t) => t.id.isBiggerOrEqualValue(0).not())
          ..where((t) => t.id.cast<String>().isIn(
                pendingRelatedIds.map((idStr) => idStr.split(':').last)
              ).not()))
        .go();
  }
}
