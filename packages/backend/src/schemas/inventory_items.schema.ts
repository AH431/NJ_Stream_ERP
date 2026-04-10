import {
  pgTable, serial, integer, timestamp, check, index,
} from 'drizzle-orm/pg-core';
import { sql } from 'drizzle-orm';
import { products } from './products.schema.ts';

/**
 * 庫存表
 *
 * DB 層 CHECK 約束（對應同步協定 v1.6 § 4 約束條件）：
 *   - quantity_on_hand >= 0
 *   - quantity_reserved <= quantity_on_hand
 * 違反任一約束 → 後端回傳 INSUFFICIENT_STOCK → 前端強制 Pull
 *
 * warehouseId：MVP 固定為 DEFAULT_WAREHOUSE_ID=1。
 * 欄位保留為 integer（無 FK）供未來多倉庫擴充，UI 暫時隱藏。
 */
export const inventoryItems = pgTable('inventory_items', {
  id:               serial('id').primaryKey(),
  productId:        integer('product_id').notNull().references(() => products.id).unique(),
  /** MVP 固定 1，保留欄位供未來多倉庫擴充，暫無 FK constraint */
  warehouseId:      integer('warehouse_id').notNull().default(1),
  /** 實際庫存數量。DB CHECK：>= 0 */
  quantityOnHand:   integer('quantity_on_hand').notNull().default(0),
  /** 已預留數量。DB CHECK：<= quantityOnHand */
  quantityReserved: integer('quantity_reserved').notNull().default(0),
  minStockLevel:    integer('min_stock_level').notNull().default(0),
  createdAt:        timestamp('created_at', { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
  updatedAt:        timestamp('updated_at', { withTimezone: true, mode: 'date' }).notNull().defaultNow().$onUpdate(() => new Date()),
  deletedAt:        timestamp('deleted_at',  { withTimezone: true, mode: 'date' }),
}, (table) => [
  check('chk_qty_on_hand_non_negative',
    sql`${table.quantityOnHand} >= 0`),
  check('chk_qty_reserved_lte_on_hand',
    sql`${table.quantityReserved} <= ${table.quantityOnHand}`),
  index('idx_inventory_items_product_id').on(table.productId),
]);

export type InventoryItem    = typeof inventoryItems.$inferSelect;
export type NewInventoryItem = typeof inventoryItems.$inferInsert;
