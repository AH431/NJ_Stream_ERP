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
  OrderItems,
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

  /// Schema 版本號，每次修改 Table 結構時必須 +1
  ///
  /// 版本歷史：
  ///   v1: 初始 9 張表
  ///   v2: 新增 OrderItems 表（訂單明細正規化，對應後端 order_items）
  ///
  /// 升版流程：
  ///   1. 修改 schema.dart（新增欄位 / 表）
  ///   2. schemaVersion +1
  ///   3. 在 onUpgrade 的對應 from 版本中加入 migration 操作
  ///   4. 執行 build_runner build 重新產生 database.g.dart
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        // App 首次安裝時：建立所有表
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        // App 升版時（schemaVersion 提高）：逐版處理結構變更
        // 範例：
        //   if (from < 2) { await m.addColumn(customers, customers.phone); }
        //   if (from < 3) { await m.createTable(someNewTable); }
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            // v1 → v2: 新增 OrderItems 表
            await m.createTable(orderItems);
          }
        },
      );

  /// LazyDatabase：延遲到第一次存取才真正開啟 SQLite 檔案
  /// createInBackground：在獨立 isolate 執行 I/O，避免 UI 卡頓
  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'nj_stream_erp.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}