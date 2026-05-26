import {
  pgTable, serial, integer, numeric, timestamp, varchar, index,
} from 'drizzle-orm/pg-core';
import { relations } from 'drizzle-orm';
import { quotations } from './quotations.schema.ts';
import { salesOrders } from './sales_orders.schema.ts';
import { products } from './products.schema.ts';
import { tenants } from './tenants.schema.ts';

/**
 * 報價 / 訂單明細表（正規化設計）
 *
 * 一筆 order_item 必屬於報價（quotationId）或訂單（salesOrderId）其中之一，
 * 轉訂單時由 service 層複製報價明細至對應的 salesOrderId 記錄。
 *
 * 正規化優點：
 *   - 避免 JSONB 無法做欄位索引與型別驗證
 *   - 支援逐行 LWW 更新與衝突偵測
 *   - 未來擴充折扣、備註、序號追蹤時不需 Schema migration
 */
export const orderItems = pgTable('order_items', {
  id:           serial('id').primaryKey(),
  tenantId:     integer('tenant_id').notNull().default(1).references(() => tenants.id),
  /** FK → quotations.id（報價明細，salesOrderId 為 null） */
  quotationId:  integer('quotation_id').references(() => quotations.id),
  /** FK → sales_orders.id（訂單明細，quotationId 為 null） */
  salesOrderId: integer('sales_order_id').references(() => salesOrders.id),
  productId:    integer('product_id').notNull().references(() => products.id),
  quantity:     integer('quantity').notNull(),
  /** 下單當下的單價快照（numeric，不隨 products.unitPrice 變動）*/
  unitPrice:    numeric('unit_price', { precision: 12, scale: 2 }).notNull(),
  /** subtotal = quantity × unitPrice（後端計算並儲存，避免前端精度誤差）*/
  subtotal:     numeric('subtotal', { precision: 12, scale: 2 }).notNull(),
  /** 整盤/整組備註，例如「每組 5,000 pcs」，供報價單顯示下單倍數說明 */
  lineNotes:    varchar('line_notes', { length: 500 }),
  createdAt:    timestamp('created_at', { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
  updatedAt:    timestamp('updated_at', { withTimezone: true, mode: 'date' }).notNull().defaultNow().$onUpdate(() => new Date()),
}, (table) => [
  index('idx_order_items_quotation_id').on(table.quotationId),
  index('idx_order_items_sales_order_id').on(table.salesOrderId),
  index('idx_order_items_product_id').on(table.productId),
]);

export const orderItemsRelations = relations(orderItems, ({ one }) => ({
  quotation:  one(quotations,  { fields: [orderItems.quotationId],  references: [quotations.id] }),
  salesOrder: one(salesOrders, { fields: [orderItems.salesOrderId], references: [salesOrders.id] }),
  product:    one(products,    { fields: [orderItems.productId],    references: [products.id] }),
}));

export type OrderItem    = typeof orderItems.$inferSelect;
export type NewOrderItem = typeof orderItems.$inferInsert;
