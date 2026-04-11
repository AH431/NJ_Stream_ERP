import {
  pgTable, serial, varchar, boolean, timestamp,
} from 'drizzle-orm/pg-core';
import { USER_ROLES } from '@/constants/index.js';

export const users = pgTable('users', {
  id:           serial('id').primaryKey(),
  username:     varchar('username', { length: 100 }).notNull().unique(),
  email:        varchar('email', { length: 255 }).notNull().unique(),
  password:     varchar('password', { length: 255 }).notNull(),
  role:         varchar('role', { length: 20 })
                  .notNull()
                  .$type<typeof USER_ROLES[keyof typeof USER_ROLES]>()
                  .default('sales'),
  isActive:     boolean('is_active').notNull().default(true),
  refreshToken: varchar('refresh_token', { length: 512 }),
  createdAt:    timestamp('created_at', { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
  updatedAt:    timestamp('updated_at', { withTimezone: true, mode: 'date' }).notNull().defaultNow().$onUpdate(() => new Date()),
  deletedAt:    timestamp('deleted_at',  { withTimezone: true, mode: 'date' }),
});

export type User    = typeof users.$inferSelect;
export type NewUser = typeof users.$inferInsert;
