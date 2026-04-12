import 'package:drift/drift.dart';
import 'converters/decimal_converter.dart';
import 'converters/datetime_converter.dart';

// ==============================================================================
// 1. 基礎資料表 (Master Data)
// ==============================================================================

@DataClassName('User')
class Users extends Table {
  IntColumn get id => integer()();
  TextColumn get username => text().withLength(max: 100)();
  TextColumn get role => text()(); // sales, warehouse, admin
  DateTimeColumn get updatedAt => dateTime().withConverter(const Iso8601DateTimeConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Customer')
class Customers extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text().withLength(max: 255)();
  TextColumn get contact => text().nullable().withLength(max: 255)();
  TextColumn get taxId => text().nullable().withLength(max: 20)();
  DateTimeColumn get createdAt => dateTime().withConverter(const Iso8601DateTimeConverter())();
  DateTimeColumn get updatedAt => dateTime().withConverter(const Iso8601DateTimeConverter())(); 
  DateTimeColumn get deletedAt => dateTime().nullable().withConverter(const Iso8601DateTimeConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Product')
class Products extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text().withLength(max: 255)();
  TextColumn get sku => text().withLength(max: 100)();
  TextColumn get unitPrice => text().withConverter(const DecimalConverter())(); // 對齊後端 decimal 字串
  IntColumn get minStockLevel => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withConverter(const Iso8601DateTimeConverter())();
  DateTimeColumn get updatedAt => dateTime().withConverter(const Iso8601DateTimeConverter())();
  DateTimeColumn get deletedAt => dateTime().nullable().withConverter(const Iso8601DateTimeConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

// ==============================================================================
// 2. 業務單據表 (Transactions)
// ==============================================================================

@DataClassName('Quotation')
class Quotations extends Table {
  IntColumn get id => integer()();
  IntColumn get customerId => integer()();
  IntColumn get createdBy => integer()();
  TextColumn get items => text()(); // 存儲 JSON 化的 List<QuotationItem>
  TextColumn get totalAmount => text().withConverter(const DecimalConverter())();
  TextColumn get taxAmount => text().withConverter(const DecimalConverter())();
  TextColumn get status => text()(); // draft, sent, converted, expired
  IntColumn get convertedToOrderId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withConverter(const Iso8601DateTimeConverter())();
  DateTimeColumn get updatedAt => dateTime().withConverter(const Iso8601DateTimeConverter())();
  DateTimeColumn get deletedAt => dateTime().nullable().withConverter(const Iso8601DateTimeConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SalesOrder')
class SalesOrders extends Table {
  IntColumn get id => integer()();
  IntColumn get quotationId => integer().nullable()(); // First-to-Sync wins 關鍵
  IntColumn get customerId => integer()();
  IntColumn get createdBy => integer()();
  TextColumn get status => text()(); // pending, confirmed, shipped, cancelled
  DateTimeColumn get confirmedAt => dateTime().nullable().withConverter(const Iso8601DateTimeConverter())();
  DateTimeColumn get shippedAt => dateTime().nullable().withConverter(const Iso8601DateTimeConverter())();
  DateTimeColumn get createdAt => dateTime().withConverter(const Iso8601DateTimeConverter())();
  DateTimeColumn get updatedAt => dateTime().withConverter(const Iso8601DateTimeConverter())();
  DateTimeColumn get deletedAt => dateTime().nullable().withConverter(const Iso8601DateTimeConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

// ==============================================================================
// 3. 庫存模組 (Inventory)
// ==============================================================================

@DataClassName('InventoryItem')
class InventoryItems extends Table {
  IntColumn get id => integer()();
  IntColumn get productId => integer()();
  IntColumn get warehouseId => integer().withDefault(const Constant(1))();
  IntColumn get quantityOnHand => integer().check(quantityOnHand.isBiggerOrEqualValue(0))(); // 約束：不得小於 0
  IntColumn get quantityReserved => integer().check(quantityReserved.isBiggerOrEqualValue(0))();
  DateTimeColumn get createdAt => dateTime().withConverter(const Iso8601DateTimeConverter())();
  DateTimeColumn get updatedAt => dateTime().withConverter(const Iso8601DateTimeConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

/// 用於儲存離線期間產生的庫存異動操作
@DataClassName('InventoryDelta')
class InventoryDeltas extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get inventoryItemId => integer()();
  IntColumn get productId => integer()();
  IntColumn get amount => integer().check(amount.isBiggerThanValue(0))();
  TextColumn get deltaType => text()(); // in, reserve, cancel, out
  IntColumn get relatedOrderId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withConverter(const Iso8601DateTimeConverter())();
}

// ==============================================================================
// 4. 同步與冪等性 (Sync & Idempotency)
// ==============================================================================

@DataClassName('ProcessedOperation')
class ProcessedOperations extends Table {
  TextColumn get operationId => text()(); // UUID v4
  TextColumn get entityType => text()(); // customer, product, etc.
  TextColumn get operationType => text()(); // create, update, delete, delta_update
  DateTimeColumn get processedAt => dateTime().withConverter(const Iso8601DateTimeConverter())();

  @override
  Set<Column> get primaryKey => {operationId};
}

// ==============================================================================
// 5. PendingOperations
// ==============================================================================

// 索引：entity_type / related_entity / status / created_at 是 Sync 最常查的維度
@TableIndex(name: 'idx_pending_entity_type', columns: {#entityType})
@TableIndex(name: 'idx_pending_related_entity', columns: {#relatedEntityId})
@TableIndex(name: 'idx_pending_status', columns: {#status})
@TableIndex(name: 'idx_pending_created_at', columns: {#createdAt})
@DataClassName('PendingOperation')
class PendingOperations extends Table {
  IntColumn get id => integer().autoIncrement()();

  // UUID，由前端產生，用於與後端 processed_operations 做冪等
  TextColumn get operationId => text().withLength(min: 36, max: 36)();

  // 關聯實體 ID，方便檢索與優化同步邏輯 e.g. "customer:101"
  TextColumn get relatedEntityId => text().nullable()();

  TextColumn get entityType => text()();        // customer, product, quotation, sales_order, inventory_delta
  TextColumn get operationType => text()();     // create, update, delete, delta_update
  TextColumn get deltaType => text().nullable()(); // reserve, cancel, out, in

  // 嚴格升序依據（Sync Contract 核心要求）
  DateTimeColumn get createdAt =>
      dateTime().withConverter(const Iso8601DateTimeConverter())();

  // payload 存完整 JSON 字串（全快照）
  TextColumn get payload => text()();

  // 佇列狀態管理
  TextColumn get status =>
      text().check(status.isIn(['pending', 'syncing', 'succeeded', 'failed'])).withDefault(const Constant('pending'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastAttemptAt =>
      dateTime().nullable().withConverter(const Iso8601DateTimeConverter())();
  TextColumn get errorMessage => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  // operationId 全局唯一，確保冪等
  @override
  List<Set<Column>> get uniqueKeys => [
        {operationId},
      ];
}