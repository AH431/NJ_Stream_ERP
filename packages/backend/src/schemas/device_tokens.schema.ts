import { pgTable, serial, integer, text, varchar, timestamp } from 'drizzle-orm/pg-core';
import { users }   from './users.schema.ts';
import { tenants } from './tenants.schema.ts';

export const deviceTokens = pgTable('device_tokens', {
  id:        serial('id').primaryKey(),
  tenantId:  integer('tenant_id').notNull().default(1).references(() => tenants.id),
  userId:    integer('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  token:     text('token').notNull().unique(),
  platform:  varchar('platform', { length: 16 }).notNull().default('android'),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
});
