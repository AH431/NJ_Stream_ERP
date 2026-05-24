import {
  pgTable, serial, varchar, boolean, timestamp,
} from 'drizzle-orm/pg-core';

export const tenants = pgTable('tenants', {
  id:           serial('id').primaryKey(),
  name:         varchar('name', { length: 100 }).notNull(),
  slug:         varchar('slug', { length: 50 }).notNull().unique(),
  plan:         varchar('plan', { length: 20 }).notNull().default('basic'),
  isActive:     boolean('is_active').notNull().default(true),
  contactEmail: varchar('contact_email', { length: 255 }),
  timezone:     varchar('timezone', { length: 50 }).notNull().default('UTC'),
  onboardedAt:  timestamp('onboarded_at', { withTimezone: true, mode: 'date' }),
  createdAt:    timestamp('created_at', { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
});

export type Tenant    = typeof tenants.$inferSelect;
export type NewTenant = typeof tenants.$inferInsert;
