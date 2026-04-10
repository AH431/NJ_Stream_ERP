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
 *   6. order_items      ← 正規化明細表（取代 JSONB items）
 *   7. inventory_items  ← 含 DB CHECK 約束
 *   8. processed_operations ← 含冪等 UNIQUE + 兩個索引
 *
 * Relations 集中定義於此檔案，避免各 schema 檔案之間的循環引用。
 */

// ── Table exports ─────────────────────────────────────────
export * from './users.schema.js';
export * from './customers.schema.js';
export * from './products.schema.js';
export * from './quotations.schema.js';
export * from './sales_orders.schema.js';
export * from './order_items.schema.js';
export * from './inventory_items.schema.js';
export * from './processed_operations.schema.js';

// ── Relations ─────────────────────────────────────────────
import { relations } from 'drizzle-orm';
import { users }               from './users.schema.js';
import { customers }           from './customers.schema.js';
import { products }            from './products.schema.js';
import { quotations }          from './quotations.schema.js';
import { salesOrders }         from './sales_orders.schema.js';
import { orderItems }          from './order_items.schema.js';
import { inventoryItems }      from './inventory_items.schema.js';

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
export { orderItemsRelations } from './order_items.schema.js';

// inventory_items → product
export const inventoryItemsRelations = relations(inventoryItems, ({ one }) => ({
  product: one(products, {
    fields:     [inventoryItems.productId],
    references: [products.id],
  }),
}));
