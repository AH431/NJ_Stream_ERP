-- Rollback script for migrations 0011_tenants + 0012_add_tenant_id
-- Usage (staging only, NEVER production):
--   docker exec -i nj-erp-postgres psql -U postgres -d nj_erp < packages/backend/drizzle/rollback_0011_0012.sql
--
-- Removes all tenant_id columns, FK constraints, and indexes added in 0012,
-- then drops the tenants table added in 0011.
--
-- Order: remove child FK refs → drop tenant_id from 12 business tables
--         → remove forecast FK back-fills → drop tenants table

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 0. FK back-fill rollback: demand_forecasts + forecast_jobs
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE "demand_forecasts"
  DROP CONSTRAINT IF EXISTS "demand_forecasts_tenant_id_tenants_id_fk";

ALTER TABLE "forecast_jobs"
  DROP CONSTRAINT IF EXISTS "forecast_jobs_tenant_id_tenants_id_fk";

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. audit_logs
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE "audit_logs"
  DROP CONSTRAINT IF EXISTS "audit_logs_tenant_id_tenants_id_fk";
DROP INDEX IF EXISTS "idx_audit_logs_tenant_id";
ALTER TABLE "audit_logs"
  DROP COLUMN IF EXISTS "tenant_id";

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. anomalies
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE "anomalies"
  DROP CONSTRAINT IF EXISTS "anomalies_tenant_id_tenants_id_fk";
DROP INDEX IF EXISTS "idx_anomalies_tenant_id";
ALTER TABLE "anomalies"
  DROP COLUMN IF EXISTS "tenant_id";

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. order_items
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE "order_items"
  DROP CONSTRAINT IF EXISTS "order_items_tenant_id_tenants_id_fk";
DROP INDEX IF EXISTS "idx_order_items_tenant_id";
ALTER TABLE "order_items"
  DROP COLUMN IF EXISTS "tenant_id";

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. sales_orders
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE "sales_orders"
  DROP CONSTRAINT IF EXISTS "sales_orders_tenant_id_tenants_id_fk";
DROP INDEX IF EXISTS "idx_sales_orders_tenant_id";
ALTER TABLE "sales_orders"
  DROP COLUMN IF EXISTS "tenant_id";

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. device_tokens
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE "device_tokens"
  DROP CONSTRAINT IF EXISTS "device_tokens_tenant_id_tenants_id_fk";
DROP INDEX IF EXISTS "idx_device_tokens_tenant_id";
ALTER TABLE "device_tokens"
  DROP COLUMN IF EXISTS "tenant_id";

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. customer_interactions
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE "customer_interactions"
  DROP CONSTRAINT IF EXISTS "customer_interactions_tenant_id_tenants_id_fk";
DROP INDEX IF EXISTS "idx_customer_interactions_tenant_id";
ALTER TABLE "customer_interactions"
  DROP COLUMN IF EXISTS "tenant_id";

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. inventory_items
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE "inventory_items"
  DROP CONSTRAINT IF EXISTS "inventory_items_tenant_id_tenants_id_fk";
DROP INDEX IF EXISTS "idx_inventory_items_tenant_id";
ALTER TABLE "inventory_items"
  DROP COLUMN IF EXISTS "tenant_id";

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. quotations
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE "quotations"
  DROP CONSTRAINT IF EXISTS "quotations_tenant_id_tenants_id_fk";
DROP INDEX IF EXISTS "idx_quotations_tenant_id";
ALTER TABLE "quotations"
  DROP COLUMN IF EXISTS "tenant_id";

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. processed_operations
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE "processed_operations"
  DROP CONSTRAINT IF EXISTS "processed_operations_tenant_id_tenants_id_fk";
DROP INDEX IF EXISTS "idx_processed_operations_tenant_id";
ALTER TABLE "processed_operations"
  DROP COLUMN IF EXISTS "tenant_id";

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. users
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE "users"
  DROP CONSTRAINT IF EXISTS "users_tenant_id_tenants_id_fk";
DROP INDEX IF EXISTS "idx_users_tenant_id";
ALTER TABLE "users"
  DROP COLUMN IF EXISTS "tenant_id";

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. products
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE "products"
  DROP CONSTRAINT IF EXISTS "products_tenant_id_tenants_id_fk";
DROP INDEX IF EXISTS "idx_products_tenant_id";
ALTER TABLE "products"
  DROP COLUMN IF EXISTS "tenant_id";

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. customers
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE "customers"
  DROP CONSTRAINT IF EXISTS "customers_tenant_id_tenants_id_fk";
DROP INDEX IF EXISTS "idx_customers_tenant_id";
ALTER TABLE "customers"
  DROP COLUMN IF EXISTS "tenant_id";

-- ─────────────────────────────────────────────────────────────────────────────
-- 0011: drop tenants table (after all FK references removed)
-- ─────────────────────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS "tenants";

COMMIT;
