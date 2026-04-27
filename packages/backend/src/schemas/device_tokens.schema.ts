import { pgTable, serial, integer, text, varchar, timestamp } from 'drizzle-orm/pg-core';
import { users } from './users.schema.ts';

export const deviceTokens = pgTable('device_tokens', {
  id:        serial('id').primaryKey(),
  userId:    integer('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  token:     text('token').notNull().unique(),
  platform:  varchar('platform', { length: 16 }).notNull().default('android'),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
});
