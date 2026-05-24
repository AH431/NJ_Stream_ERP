import {
  pgTable, serial, integer, date, numeric, varchar, timestamp, uuid, uniqueIndex, index,
} from 'drizzle-orm/pg-core';
import { products } from './products.schema.ts';
import { tenants } from './tenants.schema.ts';

export const demandForecasts = pgTable('demand_forecasts', {
  id:           serial('id').primaryKey(),
  productId:    integer('product_id').notNull().references(() => products.id),
  tenantId:     integer('tenant_id').notNull().references(() => tenants.id),
  weekStart:    date('week_start', { mode: 'string' }).notNull(),
  forecastQty:  numeric('forecast_qty', { precision: 10, scale: 2 }).notNull(),
  lowerBound:   numeric('lower_bound',  { precision: 10, scale: 2 }),
  upperBound:   numeric('upper_bound',  { precision: 10, scale: 2 }),
  modelVersion: varchar('model_version', { length: 20 }).notNull().default('prophet-v1'),
  generatedAt:  timestamp('generated_at', { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
  runId:        uuid('run_id').notNull(),
}, (table) => [
  uniqueIndex('uq_demand_forecasts_tenant_product_week_model')
    .on(table.tenantId, table.productId, table.weekStart, table.modelVersion),
  index('idx_demand_forecasts_tenant_product').on(table.tenantId, table.productId),
  index('idx_demand_forecasts_week_start').on(table.weekStart),
]);

export type DemandForecast    = typeof demandForecasts.$inferSelect;
export type NewDemandForecast = typeof demandForecasts.$inferInsert;
