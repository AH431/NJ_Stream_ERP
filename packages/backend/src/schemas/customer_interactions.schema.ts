import {
  pgTable, serial, integer, text, timestamp, index,
} from 'drizzle-orm/pg-core';
import { customers } from './customers.schema.ts';
import { users }     from './users.schema.ts';

export const customerInteractions = pgTable('customer_interactions', {
  id:         serial('id').primaryKey(),
  customerId: integer('customer_id').notNull().references(() => customers.id),
  note:       text('note').notNull(),
  createdBy:  integer('created_by').references(() => users.id),
  createdAt:  timestamp('created_at', { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
  updatedAt:  timestamp('updated_at', { withTimezone: true, mode: 'date' }).notNull().defaultNow().$onUpdate(() => new Date()),
  deletedAt:  timestamp('deleted_at', { withTimezone: true, mode: 'date' }),
}, (table) => [
  index('idx_customer_interactions_customer_id').on(table.customerId),
  index('idx_customer_interactions_updated_at').on(table.updatedAt),
]);

export type CustomerInteraction    = typeof customerInteractions.$inferSelect;
export type NewCustomerInteraction = typeof customerInteractions.$inferInsert;
