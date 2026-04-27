import {
  pgTable, serial, integer, varchar, timestamp,
} from 'drizzle-orm/pg-core';

export const customers = pgTable('customers', {
  id:               serial('id').primaryKey(),
  name:             varchar('name', { length: 255 }).notNull(),
  contact:          varchar('contact', { length: 255 }),
  email:            varchar('email', { length: 255 }),
  taxId:            varchar('tax_id', { length: 20 }),
  paymentTermsDays: integer('payment_terms_days').notNull().default(30),
  createdAt:        timestamp('created_at', { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
  updatedAt:        timestamp('updated_at', { withTimezone: true, mode: 'date' }).notNull().defaultNow().$onUpdate(() => new Date()),
  deletedAt:        timestamp('deleted_at',  { withTimezone: true, mode: 'date' }),
});

export type Customer    = typeof customers.$inferSelect;
export type NewCustomer = typeof customers.$inferInsert;
