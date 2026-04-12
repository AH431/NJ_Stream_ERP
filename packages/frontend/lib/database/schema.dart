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
  DateTimeColumn get updatedAt =>
      dateTime().withConverter(const Iso8601DateTimeConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Customer')
class Customers extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text().withLength(max: 255)();
  TextColumn get contact => text().nullable().withLength(max: 255)();
  TextColumn get taxId => text().nullable().withLength(max: 20)();
  DateTimeColumn get createdAt =>
      dateTime().withConverter(const Iso8601DateTimeConverter())();
  DateTimeColumn get updatedAt =>
      dateTime().withConverter(const Iso8601DateTimeConverter())();
  DateTimeColumn get deletedAt =>
      dateTime().nullable().withConverter(const Iso8601DateTimeConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Product')
class Products extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text().withLength(max: 255)();
  TextColumn get sku => text().withLength(max: 100)();
  TextColumn get unitPrice =>
      text().withConverter(const DecimalConverter())(); // 對齊後端 decimal 字串
  IntColumn get minStockLevel =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt =>
      dateTime().withConverter(const Iso8601DateTimeConverter())();
  DateTimeColumn get updatedAt =>
      dateTime().withConverter(const Iso8601DateTimeConverter())();
  DateTimeColumn get deletedAt =>
      dateTime().nullable().withConverter(const Iso8601DateTimeConverter())();

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
  TextColumn get items => text()(); // JSON 化的 List<QuotationItem>
  TextColumn get totalAmount =>
      text().withConverter(const DecimalConverter())();
  TextColumn get taxAmount =>
      text().withConverter(const DecimalConverter())();
  TextColumn get status => text()(); // draft, sent, converted, expired
  IntColumn get convertedToOrderId => integer().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withConverter(const Iso8601DateTimeConverter())();
  DateTimeColumn get updatedAt =>
      dateTime().withConverter(const Iso8601DateTimeConverter())();
  DateTimeColumn get deletedAt =>
      dateTime().nullable().withConverter(const Iso8601DateTimeConverter())();

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
  DateTimeColumn get confirmedAt =>
      dateTime().nullable().withConverter(const Iso8601DateTimeConverter())();
  TextColumn get items => text()(); // JSON 化的 List<SalesOrderItem>
  TextColumn get totalAmount =>
      text().withConverter(const DecimalConverter())();
  TextColumn get taxAmount =>
      text().withConverter(const DecimalConverter())();
  DateTimeColumn get createdAt =>
      dateTime().withConverter(const Iso8601DateTimeConverter())();
  DateTimeColumn get updatedAt =>
      dateTime().withConverter(const Iso8601DateTimeConverter())();
  DateTimeColumn get deletedAt =>
      dateTime().nullable().withConverter(const Iso8601DateTimeConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('InventoryItem')
class InventoryItems extends Table {
  IntColumn get id => integer()();
  IntColumn get productId => integer()();
  TextColumn get quantityOnHand =>
      text().withConverter(const DecimalConverter())();
  TextColumn get quantityReserved =>
      text().withConverter(const DecimalConverter())();
  DateTimeColumn get updatedAt =>
      dateTime().withConverter(const Iso8601DateTimeConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

// ==============================================================================
// 3. 離線操作佇列 (Sync Queue)
// ==============================================================================

@DataClassName('PendingOperation')
class PendingOperations extends Table {
  // UUID 字串，對應後端 operation.id
  TextColumn get id => text()();
  TextColumn get entity => text()(); // customer, product, quotation, sales_order, inventory
  TextColumn get operation => text()(); // CREATE, UPDATE, DELETE
  IntColumn get recordId => integer().nullable()(); // 已有後端 ID 時填入
  TextColumn get payload => text()(); // JSON 序列化的欄位變動
  DateTimeColumn get createdAt =>
      dateTime().withConverter(const Iso8601DateTimeConverter())();
  IntColumn get retryCount =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
