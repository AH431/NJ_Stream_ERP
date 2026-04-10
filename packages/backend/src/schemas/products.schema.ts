import {
  pgTable, serial, varchar, integer, numeric, timestamp,
} from 'drizzle-orm/pg-core';

export const products = pgTable('products', {
  id:            serial('id').primaryKey(),
  name:          varchar('name', { length: 255 }).notNull(),
  sku:           varchar('sku', { length: 100 }).notNull().unique(),
  unitPrice:     numeric('unit_price', { precision: 12, scale: 2 }).notNull(),
  minStockLevel: integer('min_stock_level').notNull().default(0),
  createdAt:     timestamp('created_at', { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
  updatedAt:     timestamp('updated_at', { withTimezone: true, mode: 'date' }).notNull().defaultNow().$onUpdate(() => new Date()),
  deletedAt:     timestamp('deleted_at',  { withTimezone: true, mode: 'date' }),
});

export type Product    = typeof products.$inferSelect;
export type NewProduct = typeof products.$inferInsert;
