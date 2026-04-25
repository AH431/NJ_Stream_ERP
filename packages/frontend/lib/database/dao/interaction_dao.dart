import 'package:drift/drift.dart';
import '../database.dart';

extension InteractionDao on AppDatabase {
  /// 取得客戶的活躍互動記錄（依建立時間降序）
  Future<List<CustomerInteraction>> getActiveInteractions(int customerId) =>
      (select(customerInteractions)
        ..where((t) => t.customerId.equals(customerId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .get();

  /// 監聽客戶的活躍互動記錄（StreamBuilder 用）
  Stream<List<CustomerInteraction>> watchActiveInteractions(int customerId) =>
      (select(customerInteractions)
        ..where((t) => t.customerId.equals(customerId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();

  /// 插入互動記錄（offline create，id 為前端配發負數）
  Future<CustomerInteraction> insertInteraction(
      CustomerInteractionsCompanion data) =>
      into(customerInteractions).insertReturning(data);

  /// 軟刪除互動記錄
  Future<void> softDeleteInteraction(int id, DateTime now) =>
      (update(customerInteractions)..where((t) => t.id.equals(id)))
      .write(CustomerInteractionsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ));

  /// Upsert（供 sync pull 使用）
  Future<void> upsertInteractionFromServer(
      CustomerInteractionsCompanion data) async {
    await into(customerInteractions).insertOnConflictUpdate(data);
  }
}
