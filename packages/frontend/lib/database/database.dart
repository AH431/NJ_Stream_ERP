import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'schema.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  // Master Data
  Users,
  Customers,
  Products,
  // Transactions
  Quotations,
  SalesOrders,
  // Inventory
  InventoryItems,
  InventoryDeltas,
  // Sync & Idempotency
  ProcessedOperations,
  PendingOperations,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 測試用：直接傳入 QueryExecutor（e.g. NativeDatabase.memory()）
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1; // 之後 migration 時會慢慢增加

  // 簡單的 migration 策略（之後可改成更進階）
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // 未來 schemaVersion 變更時，在這裡處理 migration
          // 例如：if (from < 2) { await m.addColumn(...); }
        },
      );

  // 建議寫在 class 內部 + static
  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'nj_stream_erp.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}