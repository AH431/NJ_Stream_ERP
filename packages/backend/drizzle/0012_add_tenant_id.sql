-- Migration 0012: add tenant_id to 12 business tables
-- Phase 4C Sprint M6.2 (PR-6)
--
-- Adds tenant_id INTEGER NOT NULL DEFAULT 1 + FK to tenants(id) for all
-- pre-existing business tables.  DEFAULT 1 maps every existing row to the
-- "Demo Company" tenant seeded in migration 0011, so no separate UPDATE step
-- is needed and the NOT NULL constraint is satisfied immediately.
--
-- Tables covered (ordered by dependency depth):
--   1. customers            6. inventory_items
--   2. products             7. customer_interactions
--   3. users                8. device_tokens
--   4. processed_operations 9. sales_orders
--   5. quotations          10. order_items
--                          11. anomalies
--                          12. audit_logs
--
-- FK back-fill for tables that already carry tenant_id (no FK yet):
--   • demand_forecasts  (added in 0009)
--   • forecast_jobs     (added in 0010)

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. customers
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE "customers"
  ADD COLUMN IF NOT EXISTS "tenant_id" integer NOT NULL DEFAULT 1;
--> statement-breakpoint
DO $$ BEGIN
  ALTER TABLE "customers"
    ADD CONSTRAINT "customers_tenant_id_tenants_id_fk"
    FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id")
    ON DELETE no action ON UPDATE no action;
EXCEPTION WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_customers_tenant_id"
  ON "customers" USING btree ("tenant_id");

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. products
-- ─────────────────────────────────────────────────────────────────────────────
--> statement-breakpoint
ALTER TABLE "products"
  ADD COLUMN IF NOT EXISTS "tenant_id" integer NOT NULL DEFAULT 1;
--> statement-breakpoint
DO $$ BEGIN
  ALTER TABLE "products"
    ADD CONSTRAINT "products_tenant_id_tenants_id_fk"
    FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id")
    ON DELETE no action ON UPDATE no action;
EXCEPTION WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_products_tenant_id"
  ON "products" USING btree ("tenant_id");

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. users
-- ─────────────────────────────────────────────────────────────────────────────
--> statement-breakpoint
ALTER TABLE "users"
  ADD COLUMN IF NOT EXISTS "tenant_id" integer NOT NULL DEFAULT 1;
--> statement-breakpoint
DO $$ BEGIN
  ALTER TABLE "users"
    ADD CONSTRAINT "users_tenant_id_tenants_id_fk"
    FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id")
    ON DELETE no action ON UPDATE no action;
EXCEPTION WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_users_tenant_id"
  ON "users" USING btree ("tenant_id");

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. processed_operations
-- ─────────────────────────────────────────────────────────────────────────────
--> statement-breakpoint
ALTER TABLE "processed_operations"
  ADD COLUMN IF NOT EXISTS "tenant_id" integer NOT NULL DEFAULT 1;
--> statement-breakpoint
DO $$ BEGIN
  ALTER TABLE "processed_operations"
    ADD CONSTRAINT "processed_operations_tenant_id_tenants_id_fk"
    FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id")
    ON DELETE no action ON UPDATE no action;
EXCEPTION WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_processed_operations_tenant_id"
  ON "processed_operations" USING btree ("tenant_id");

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. quotations
-- ─────────────────────────────────────────────────────────────────────────────
--> statement-breakpoint
ALTER TABLE "quotations"
  ADD COLUMN IF NOT EXISTS "tenant_id" integer NOT NULL DEFAULT 1;
--> statement-breakpoint
DO $$ BEGIN
  ALTER TABLE "quotations"
    ADD CONSTRAINT "quotations_tenant_id_tenants_id_fk"
    FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id")
    ON DELETE no action ON UPDATE no action;
EXCEPTION WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_quotations_tenant_id"
  ON "quotations" USING btree ("tenant_id");

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. inventory_items
-- ─────────────────────────────────────────────────────────────────────────────
--> statement-breakpoint
ALTER TABLE "inventory_items"
  ADD COLUMN IF NOT EXISTS "tenant_id" integer NOT NULL DEFAULT 1;
--> statement-breakpoint
DO $$ BEGIN
  ALTER TABLE "inventory_items"
    ADD CONSTRAINT "inventory_items_tenant_id_tenants_id_fk"
    FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id")
    ON DELETE no action ON UPDATE no action;
EXCEPTION WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_inventory_items_tenant_id"
  ON "inventory_items" USING btree ("tenant_id");

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. customer_interactions
-- ─────────────────────────────────────────────────────────────────────────────
--> statement-breakpoint
ALTER TABLE "customer_interactions"
  ADD COLUMN IF NOT EXISTS "tenant_id" integer NOT NULL DEFAULT 1;
--> statement-breakpoint
DO $$ BEGIN
  ALTER TABLE "customer_interactions"
    ADD CONSTRAINT "customer_interactions_tenant_id_tenants_id_fk"
    FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id")
    ON DELETE no action ON UPDATE no action;
EXCEPTION WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_customer_interactions_tenant_id"
  ON "customer_interactions" USING btree ("tenant_id");

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. device_tokens
-- ─────────────────────────────────────────────────────────────────────────────
--> statement-breakpoint
ALTER TABLE "device_tokens"
  ADD COLUMN IF NOT EXISTS "tenant_id" integer NOT NULL DEFAULT 1;
--> statement-breakpoint
DO $$ BEGIN
  ALTER TABLE "device_tokens"
    ADD CONSTRAINT "device_tokens_tenant_id_tenants_id_fk"
    FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id")
    ON DELETE no action ON UPDATE no action;
EXCEPTION WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_device_tokens_tenant_id"
  ON "device_tokens" USING btree ("tenant_id");

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. sales_orders
-- ─────────────────────────────────────────────────────────────────────────────
--> statement-breakpoint
ALTER TABLE "sales_orders"
  ADD COLUMN IF NOT EXISTS "tenant_id" integer NOT NULL DEFAULT 1;
--> statement-breakpoint
DO $$ BEGIN
  ALTER TABLE "sales_orders"
    ADD CONSTRAINT "sales_orders_tenant_id_tenants_id_fk"
    FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id")
    ON DELETE no action ON UPDATE no action;
EXCEPTION WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_sales_orders_tenant_id"
  ON "sales_orders" USING btree ("tenant_id");

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. order_items
-- ─────────────────────────────────────────────────────────────────────────────
--> statement-breakpoint
ALTER TABLE "order_items"
  ADD COLUMN IF NOT EXISTS "tenant_id" integer NOT NULL DEFAULT 1;
--> statement-breakpoint
DO $$ BEGIN
  ALTER TABLE "order_items"
    ADD CONSTRAINT "order_items_tenant_id_tenants_id_fk"
    FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id")
    ON DELETE no action ON UPDATE no action;
EXCEPTION WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_order_items_tenant_id"
  ON "order_items" USING btree ("tenant_id");

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. anomalies
-- ─────────────────────────────────────────────────────────────────────────────
--> statement-breakpoint
ALTER TABLE "anomalies"
  ADD COLUMN IF NOT EXISTS "tenant_id" integer NOT NULL DEFAULT 1;
--> statement-breakpoint
DO $$ BEGIN
  ALTER TABLE "anomalies"
    ADD CONSTRAINT "anomalies_tenant_id_tenants_id_fk"
    FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id")
    ON DELETE no action ON UPDATE no action;
EXCEPTION WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_anomalies_tenant_id"
  ON "anomalies" USING btree ("tenant_id");

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. audit_logs
-- ─────────────────────────────────────────────────────────────────────────────
--> statement-breakpoint
ALTER TABLE "audit_logs"
  ADD COLUMN IF NOT EXISTS "tenant_id" integer NOT NULL DEFAULT 1;
--> statement-breakpoint
DO $$ BEGIN
  ALTER TABLE "audit_logs"
    ADD CONSTRAINT "audit_logs_tenant_id_tenants_id_fk"
    FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id")
    ON DELETE no action ON UPDATE no action;
EXCEPTION WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_audit_logs_tenant_id"
  ON "audit_logs" USING btree ("tenant_id");

-- ─────────────────────────────────────────────────────────────────────────────
-- FK back-fill: demand_forecasts (column added in 0009, tenants not yet existed)
-- ─────────────────────────────────────────────────────────────────────────────
--> statement-breakpoint
DO $$ BEGIN
  ALTER TABLE "demand_forecasts"
    ADD CONSTRAINT "demand_forecasts_tenant_id_tenants_id_fk"
    FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id")
    ON DELETE no action ON UPDATE no action;
EXCEPTION WHEN duplicate_object THEN null;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- FK back-fill: forecast_jobs (column added in 0010, tenants not yet existed)
-- ─────────────────────────────────────────────────────────────────────────────
--> statement-breakpoint
DO $$ BEGIN
  ALTER TABLE "forecast_jobs"
    ADD CONSTRAINT "forecast_jobs_tenant_id_tenants_id_fk"
    FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id")
    ON DELETE no action ON UPDATE no action;
EXCEPTION WHEN duplicate_object THEN null;
END $$;
