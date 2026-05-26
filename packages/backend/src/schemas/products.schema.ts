import {
  pgTable, serial, varchar, integer, numeric, timestamp,
} from 'drizzle-orm/pg-core';
import { tenants } from './tenants.schema.ts';

export const products = pgTable('products', {
  id:            serial('id').primaryKey(),
  tenantId:      integer('tenant_id').notNull().default(1).references(() => tenants.id),
  name:          varchar('name', { length: 255 }).notNull(),
  sku:           varchar('sku', { length: 100 }).notNull().unique(),
  unitPrice:     numeric('unit_price', { precision: 12, scale: 2 }).notNull(),
  costPrice:     numeric('cost_price', { precision: 12, scale: 2 }),
  minStockLevel: integer('min_stock_level').notNull().default(0),
  /** 標準包裝量 (Standard Package Quantity): 每組/整盤/整捲 的零件數量。
   *  下單數量必須為 spq 的整數倍。預設值 1 表示以個別單件下單。 */
  spq:           integer('spq').notNull().default(1),
  /** 最小訂購量 (Minimum Order Quantity): 最少需下幾「組」。
   *  實際最小下單件數 = moq × spq。預設值 1。 */
  moq:           integer('moq').notNull().default(1),
  createdAt:     timestamp('created_at', { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
  updatedAt:     timestamp('updated_at', { withTimezone: true, mode: 'date' }).notNull().defaultNow().$onUpdate(() => new Date()),
  deletedAt:     timestamp('deleted_at',  { withTimezone: true, mode: 'date' }),
});

export type Product    = typeof products.$inferSelect;
export type NewProduct = typeof products.$inferInsert;
