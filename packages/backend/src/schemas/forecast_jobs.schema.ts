import {
  pgTable, uuid, integer, varchar, timestamp, text, index,
} from 'drizzle-orm/pg-core';
import { tenants } from './tenants.schema.ts';

export const forecastJobs = pgTable('forecast_jobs', {
  id:             uuid('id').primaryKey(),
  tenantId:       integer('tenant_id').notNull().references(() => tenants.id),
  requestedBy:    integer('requested_by'),
  triggerType:    varchar('trigger_type', { length: 20 }).notNull(),
  status:         varchar('status', { length: 20 }).notNull(),
  weeksAhead:     integer('weeks_ahead').notNull(),
  modelVersion:   varchar('model_version', { length: 20 }).notNull(),
  startedAt:      timestamp('started_at',       { withTimezone: true, mode: 'date' }),
  finishedAt:     timestamp('finished_at',      { withTimezone: true, mode: 'date' }),
  leaseExpiresAt: timestamp('lease_expires_at', { withTimezone: true, mode: 'date' }),
  generatedCnt:   integer('generated_cnt').notNull().default(0),
  skippedCnt:     integer('skipped_cnt').notNull().default(0),
  errorSummary:   text('error_summary'),
  createdAt:      timestamp('created_at', { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
}, (table) => [
  index('idx_forecast_jobs_tenant_status').on(table.tenantId, table.status),
  index('idx_forecast_jobs_created_at').on(table.createdAt),
]);

export type ForecastJob    = typeof forecastJobs.$inferSelect;
export type NewForecastJob = typeof forecastJobs.$inferInsert;
