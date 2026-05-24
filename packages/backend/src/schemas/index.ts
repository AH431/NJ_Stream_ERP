/**
 * Drizzle Schema 統一匯出（全 8 表 + Relations）
 * drizzle.config.ts 指向此檔案作為 schema entry point
 *
 * 表清單：
 *   1. users
 *   2. customers
 *   3. products
 *   4. quotations
 *   5. sales_orders
 *   6. order_items          ← 正規化明細表（取代 JSONB items）
 *   7. inventory_items      ← 含 DB CHECK 約束
 *   8. processed_operations ← 含冪等 UNIQUE + 兩個索引
 *   9. anomalies            ← P2-DB-01：異常事件記錄（Phase 2）
 *  10. device_tokens        ← FCM push 通知裝置 token
 *  11. audit_logs           ← Phase 3 AI 助理稽核記錄（不混用 processed_operations）
 *  12. demand_forecasts     ← Phase 4 PR-3：需求預測結果（每週彙總）
 *  13. forecast_jobs        ← Phase 4 PR-3：預測 job ledger / lease
 *  14. tenants              ← Phase 4C M6.1：租戶根表（FK 來源）
 *
 * Migration 0012 (M6.2)：上述全部業務表均已加 tenant_id + FK → tenants(id)。
 *
 * Relations 集中定義於此檔案，避免各 schema 檔案之間的循環引用。
 */

// ── Table exports ─────────────────────────────────────────
export * from './tenants.schema.ts';
export * from './users.schema.ts';
export * from './customers.schema.ts';
export * from './products.schema.ts';
export * from './quotations.schema.ts';
export * from './sales_orders.schema.ts';
export * from './order_items.schema.ts';
export * from './inventory_items.schema.ts';
export * from './processed_operations.schema.ts';
export * from './anomalies.schema.ts';
export * from './customer_interactions.schema.ts';
export * from './device_tokens.schema.ts';
export * from './audit_logs.schema.ts';
export * from './demand_forecasts.schema.ts';
export * from './forecast_jobs.schema.ts';

// ── Relations ─────────────────────────────────────────────
import { relations } from 'drizzle-orm';
import { users }               from './users.schema.ts';
import { customers }           from './customers.schema.ts';
import { products }            from './products.schema.ts';
import { quotations }          from './quotations.schema.ts';
import { salesOrders }         from './sales_orders.schema.ts';
import { orderItems }          from './order_items.schema.ts';
import { inventoryItems }      from './inventory_items.schema.ts';

// users → quotations, sales_orders
export const usersRelations = relations(users, ({ many }) => ({
  quotations:  many(quotations),
  salesOrders: many(salesOrders),
}));

// customers → quotations, sales_orders
export const customersRelations = relations(customers, ({ many }) => ({
  quotations:  many(quotations),
  salesOrders: many(salesOrders),
}));

// products → order_items, inventory_items
export const productsRelations = relations(products, ({ many, one }) => ({
  orderItems:    many(orderItems),
  inventoryItem: one(inventoryItems, {
    fields:     [products.id],
    references: [inventoryItems.productId],
  }),
}));

// quotations → customer, createdBy, sales_order, order_items
export const quotationsRelations = relations(quotations, ({ one, many }) => ({
  customer:   one(customers, {
    fields:     [quotations.customerId],
    references: [customers.id],
  }),
  createdBy:  one(users, {
    fields:     [quotations.createdBy],
    references: [users.id],
  }),
  salesOrder: one(salesOrders, {
    fields:     [quotations.convertedToOrderId],
    references: [salesOrders.id],
  }),
  orderItems: many(orderItems),
}));

// sales_orders → quotation, customer, createdBy, order_items
export const salesOrdersRelations = relations(salesOrders, ({ one, many }) => ({
  quotation:  one(quotations, {
    fields:     [salesOrders.quotationId],
    references: [quotations.id],
  }),
  customer:   one(customers, {
    fields:     [salesOrders.customerId],
    references: [customers.id],
  }),
  createdBy:  one(users, {
    fields:     [salesOrders.createdBy],
    references: [users.id],
  }),
  orderItems: many(orderItems),
}));

// order_items relations 已定義於 order_items.schema.ts，直接 re-export
export { orderItemsRelations } from './order_items.schema.ts';

// inventory_items → product
export const inventoryItemsRelations = relations(inventoryItems, ({ one }) => ({
  product: one(products, {
    fields:     [inventoryItems.productId],
    references: [products.id],
  }),
}));
