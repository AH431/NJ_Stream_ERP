import {
  pgTable, serial, integer, varchar, timestamp,
} from 'drizzle-orm/pg-core';
import { customers } from './customers.schema.ts';
import { users } from './users.schema.ts';
import { quotations } from './quotations.schema.ts';
import type { SALES_ORDER_STATUSES, PAYMENT_STATUSES } from '@/constants/index.js';

export const salesOrders = pgTable('sales_orders', {
  id:          serial('id').primaryKey(),
  /**
   * FK → quotations.id（從報價轉入時不為 null）。
   * First-to-Sync wins：後端在建立前以 quotationId 加鎖，先到者勝。
   */
  quotationId:   integer('quotation_id').references(() => quotations.id),
  customerId:    integer('customer_id').notNull().references(() => customers.id),
  createdBy:     integer('created_by').notNull().references(() => users.id),
  status:        varchar('status', { length: 20 })
                   .notNull()
                   .$type<typeof SALES_ORDER_STATUSES[keyof typeof SALES_ORDER_STATUSES]>()
                   .default('pending'),
  paymentStatus: varchar('payment_status', { length: 20 })
                   .notNull()
                   .$type<typeof PAYMENT_STATUSES[keyof typeof PAYMENT_STATUSES]>()
                   .default('unpaid'),
  confirmedAt:   timestamp('confirmed_at', { withTimezone: true, mode: 'date' }),
  shippedAt:     timestamp('shipped_at',   { withTimezone: true, mode: 'date' }),
  paidAt:        timestamp('paid_at',      { withTimezone: true, mode: 'date' }),
  dueDate:       timestamp('due_date',     { withTimezone: true, mode: 'date' }),
  createdAt:     timestamp('created_at',   { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
  updatedAt:     timestamp('updated_at',   { withTimezone: true, mode: 'date' }).notNull().defaultNow().$onUpdate(() => new Date()),
  deletedAt:     timestamp('deleted_at',   { withTimezone: true, mode: 'date' }),
});

export type SalesOrder    = typeof salesOrders.$inferSelect;
export type NewSalesOrder = typeof salesOrders.$inferInsert;
