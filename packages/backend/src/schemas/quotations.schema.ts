import {
  pgTable, serial, integer, numeric, varchar, timestamp,
} from 'drizzle-orm/pg-core';
import { customers } from './customers.schema.ts';
import { users } from './users.schema.ts';
import type { QUOTATION_STATUSES } from '@/constants/index.js';

/**
 * 報價表
 * 明細資料正規化至 order_items 表，不使用 JSONB items 欄位。
 * totalAmount / taxAmount 由 service 層從 order_items 加總後寫入。
 */
export const quotations = pgTable('quotations', {
  id:                 serial('id').primaryKey(),
  customerId:         integer('customer_id').notNull().references(() => customers.id),
  createdBy:          integer('created_by').notNull().references(() => users.id),
  totalAmount:        numeric('total_amount', { precision: 12, scale: 2 }).notNull(),
  taxAmount:          numeric('tax_amount',   { precision: 12, scale: 2 }).notNull(),
  status:             varchar('status', { length: 20 })
                        .notNull()
                        .$type<typeof QUOTATION_STATUSES[keyof typeof QUOTATION_STATUSES]>()
                        .default('draft'),
  /**
   * 轉換後對應的 sales_order.id。
   * First-to-Sync wins：此欄位非 null 時，後續轉單請求回傳 FORBIDDEN_OPERATION。
   */
  convertedToOrderId: integer('converted_to_order_id'),
  createdAt:          timestamp('created_at', { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
  updatedAt:          timestamp('updated_at', { withTimezone: true, mode: 'date' }).notNull().defaultNow().$onUpdate(() => new Date()),
  deletedAt:          timestamp('deleted_at',  { withTimezone: true, mode: 'date' }),
});

export type Quotation    = typeof quotations.$inferSelect;
export type NewQuotation = typeof quotations.$inferInsert;
