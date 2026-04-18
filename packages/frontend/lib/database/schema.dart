// ==============================================================================
// NJ_Stream_ERP — Drift Schema
//
// 設計原則：
//   1. 時間欄位全部用 TEXT + Iso8601DateTimeConverter（對齊後端 ISO-8601 UTC 格式）
//   2. 金額欄位全部用 TEXT + DecimalConverter（避免浮點誤差）
//   3. 軟刪除（soft-delete）：刪除時寫入 deleted_at，不做 hard delete
//   4. 所有 id 對應後端 PostgreSQL integer PK，不使用 autoIncrement（由後端配發）
//      例外：InventoryDeltas、PendingOperations 使用 autoIncrement（本地產生）
//   5. PendingOperations 是離線同步的核心，設計詳見下方
// ==============================================================================

import 'package:drift/drift.dart';
import 'converters/decimal_converter.dart';
import 'converters/datetime_converter.dart';

// ==============================================================================
// 1. 基礎資料表 (Master Data)
// ==============================================================================

/// 系統使用者（對應後端 users 表）
/// role 只有三種：sales（業務）/ warehouse（倉管）/ admin（管理員）
/// 僅同步 id / username / role / updatedAt，密碼雜湊不下載到前端
@DataClassName('User')
class Users extends Table {
  IntColumn get id => integer()();
  TextColumn get username => text().withLength(max: 100)();
  TextColumn get role => text()(); // sales, warehouse, admin
  TextColumn get updatedAt => text().map(const Iso8601DateTimeConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

/// 客戶主檔
/// deletedAt 非 null 表示軟刪除，UI 應過濾掉 deletedAt != null 的記錄
/// Sync Contract LWW（Last-Write-Wins）：以 updatedAt 判斷哪一方的資料較新
@DataClassName('Customer')
class Customers extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text().withLength(max: 255)();
  TextColumn get contact => text().nullable().withLength(max: 255)();
  TextColumn get email   => text().nullable().withLength(max: 255)();
  TextColumn get taxId   => text().nullable().withLength(max: 20)();
  TextColumn get createdAt => text().map(const Iso8601DateTimeConverter())();
  TextColumn get updatedAt => text().map(const Iso8601DateTimeConverter())(); 
  TextColumn get deletedAt => text().map(const Iso8601DateTimeConverter()).nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 產品主檔
/// unitPrice 用 DecimalConverter：後端傳 "158000.00" 字串，前端同格式儲存
/// minStockLevel：庫存低於此值時 Dashboard 顯示警示
@DataClassName('Product')
class Products extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text().withLength(max: 255)();
  TextColumn get sku => text().withLength(max: 100)();
  TextColumn get unitPrice => text().map(const DecimalConverter())(); // 對齊後端 decimal 字串
  IntColumn get minStockLevel => integer().withDefault(const Constant(0))();
  TextColumn get createdAt => text().map(const Iso8601DateTimeConverter())();
  TextColumn get updatedAt => text().map(const Iso8601DateTimeConverter())();
  TextColumn get deletedAt => text().map(const Iso8601DateTimeConverter()).nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ==============================================================================
// 2. 業務單據表 (Transactions)
// ==============================================================================

/// 報價單
/// items：JSON 字串，儲存 List<{productId, qty, unitPrice, subtotal}>
/// status 流轉：draft → sent → converted（已轉訂單）/ expired
/// convertedToOrderId：轉訂單後填入，用於前端顯示關聯
@DataClassName('Quotation')
class Quotations extends Table {
  IntColumn get id => integer()();
  IntColumn get customerId => integer()();
  IntColumn get createdBy => integer()();
  TextColumn get items => text()(); // 存儲 JSON 化的 List<QuotationItem>
  TextColumn get totalAmount => text().map(const DecimalConverter())();
  TextColumn get taxAmount => text().map(const DecimalConverter())();
  TextColumn get status => text()(); // draft, sent, converted, expired
  IntColumn get convertedToOrderId => integer().nullable()();
  TextColumn get createdAt => text().map(const Iso8601DateTimeConverter())();
  TextColumn get updatedAt => text().map(const Iso8601DateTimeConverter())();
  TextColumn get deletedAt => text().map(const Iso8601DateTimeConverter()).nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 銷售訂單
/// quotationId nullable：可以不經報價直接建單
/// First-to-Sync wins：兩台裝置同時把同一份報價轉訂單時，
///   先到後端的那筆成立，後到的後端會回傳 DATA_CONFLICT
/// status 流轉：pending → confirmed（觸發 reserve）→ shipped（觸發 out）/ cancelled
@DataClassName('SalesOrder')
class SalesOrders extends Table {
  IntColumn get id => integer()();
  IntColumn get quotationId => integer().nullable()(); // First-to-Sync wins 關鍵
  IntColumn get customerId => integer()();
  IntColumn get createdBy => integer()();
  TextColumn get status => text()(); // pending, confirmed, shipped, cancelled
  TextColumn get confirmedAt  => text().map(const Iso8601DateTimeConverter()).nullable()();
  TextColumn get reservedAt   => text().map(const Iso8601DateTimeConverter()).nullable()();
  /// 本地端標記庫存不足警示時間（不同步至伺服器）
  TextColumn get stockAlertAt => text().map(const Iso8601DateTimeConverter()).nullable()();
  TextColumn get shippedAt    => text().map(const Iso8601DateTimeConverter()).nullable()();
  TextColumn get createdAt => text().map(const Iso8601DateTimeConverter())();
  TextColumn get updatedAt => text().map(const Iso8601DateTimeConverter())();
  TextColumn get deletedAt => text().map(const Iso8601DateTimeConverter()).nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 訂單明細（對應後端 order_items 表）
/// 一筆 SalesOrder 對應多筆 OrderItems
///
/// 為什麼獨立成表（而非 JSON inline）：
///   1. 庫存鎖定精確度：reserve / out 操作是針對「明細行」，
///      正規化後可直接 SQL 加總某產品的預佔量，無需 Dart 解析 JSON
///   2. 後端對齊：後端 order_items 表確實存在，Sync 時直接對應
///
/// 為什麼 Quotations 繼續用 JSON inline（混合同步策略）：
///   報價單整單進出，Draft 階段結構鬆散，JSON 能降低表關聯複雜度；
///   一旦轉訂單，由前端解析 JSON 寫入 SalesOrders + OrderItems
@TableIndex(name: 'idx_order_items_order_id', columns: {#orderId})
@DataClassName('OrderItem')
class OrderItems extends Table {
  IntColumn get id => integer()();
  IntColumn get orderId => integer()(); // FK to SalesOrders.id
  IntColumn get productId => integer()();
  IntColumn get quantity => integer()();

  // 金額欄位：嚴格對齊 DecimalConverter（後端傳 "158000.00" 字串格式）
  TextColumn get unitPrice => text().map(const DecimalConverter())();
  TextColumn get subtotal => text().map(const DecimalConverter())();

  TextColumn get createdAt => text().map(const Iso8601DateTimeConverter())();
  TextColumn get updatedAt => text().map(const Iso8601DateTimeConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

// ==============================================================================
// 3. 庫存模組 (Inventory)
// ==============================================================================

/// 庫存快照（每個 product × warehouse 一筆）
/// quantityOnHand：實際在庫數量（CHECK >= 0，不可為負）
/// quantityReserved：已確認訂單鎖定的數量（CHECK >= 0）
/// 可出貨數 = quantityOnHand - quantityReserved
/// 這兩個欄位不直接修改，只能透過 InventoryDelta + DELTA_UPDATE 操作變更
@DataClassName('InventoryItem')
class InventoryItems extends Table {
  IntColumn get id => integer()();
  IntColumn get productId => integer()();
  IntColumn get warehouseId => integer().withDefault(const Constant(1))();
  IntColumn get quantityOnHand => integer().customConstraint('NOT NULL CHECK (quantity_on_hand >= 0)')(); // 約束：不得小於 0
  IntColumn get quantityReserved => integer().customConstraint('NOT NULL CHECK (quantity_reserved >= 0)')();
  /// 低庫存警示閾值（對應後端 inventory_items.min_stock_level）
  IntColumn get minStockLevel => integer().withDefault(const Constant(0))();
  TextColumn get createdAt => text().map(const Iso8601DateTimeConverter())();
  TextColumn get updatedAt => text().map(const Iso8601DateTimeConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

/// 用於儲存離線期間產生的庫存異動操作
@DataClassName('InventoryDelta')
class InventoryDeltas extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get inventoryItemId => integer()();
  IntColumn get productId => integer()();
  IntColumn get amount => integer().customConstraint('NOT NULL CHECK (amount > 0)')();
  TextColumn get deltaType => text()(); // in, reserve, cancel, out
  IntColumn get relatedOrderId => integer().nullable()();
  TextColumn get createdAt => text().map(const Iso8601DateTimeConverter())();
}

// ==============================================================================
// 4. 同步與冪等性 (Sync & Idempotency)
// ==============================================================================

/// 已處理操作記錄（冪等防重複）
/// 後端每次處理 operation 後回傳 operationId，前端記錄在此表
/// 下次同步前先查此表：若 operationId 已存在，跳過該 operation
/// Sync Contract §8：每週清理 30 天以上記錄
@DataClassName('ProcessedOperation')
class ProcessedOperations extends Table {
  TextColumn get operationId => text()(); // UUID v4
  TextColumn get entityType => text()(); // customer, product, etc.
  TextColumn get operationType => text()(); // create, update, delete, delta_update
  TextColumn get processedAt => text().map(const Iso8601DateTimeConverter())();

  @override
  Set<Column> get primaryKey => {operationId};
}


// ==============================================================================
// 5. PendingOperations — 離線操作佇列（核心同步機制）
//
// 設計說明：
//   離線期間所有寫入操作（建立/更新/刪除/庫存異動）都先寫入此表，
//   連線恢復後由 SyncProvider 依 id 升序批次推送到後端。
//
// 狀態流轉：
//   pending（初始）
//     → syncing（正在推送中）
//       → succeeded（後端確認）
//       → failed（後端明確拒絕，e.g. FORBIDDEN_OPERATION）
//     → pending（網路錯誤，等下次重試，retryCount++）
//
// operationId（UUID）：
//   由前端產生，對應後端 ProcessedOperations.operationId
//   uniqueKey 確保同一 operation 不會重複寫入佇列
//
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
  TextColumn get createdAt =>
      text().map(const Iso8601DateTimeConverter())();

  // payload 存完整 JSON 字串（全快照）
  TextColumn get payload => text()();

  // 佇列狀態管理
  TextColumn get status =>
      text().customConstraint("NOT NULL CHECK (status IN ('pending', 'syncing', 'succeeded', 'failed'))").withDefault(const Constant('pending'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastAttemptAt =>
      text().map(const Iso8601DateTimeConverter()).nullable()();
  TextColumn get errorMessage => text().nullable()();

  // autoIncrement() 已自動設定 id 為 PRIMARY KEY，不需再 override primaryKey
  // （同時 override 會導致 Drift codegen warning）

  // operationId 全局唯一，確保冪等
  @override
  List<Set<Column>> get uniqueKeys => [
        {operationId},
      ];
}
