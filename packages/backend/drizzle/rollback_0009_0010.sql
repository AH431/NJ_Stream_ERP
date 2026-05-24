-- Rollback script for migrations 0009_demand_forecasts + 0010_forecast_jobs
-- Usage (staging only, never production):
--   docker exec -i nj-erp-postgres psql -U <user> -d <db> < packages/backend/drizzle/rollback_0009_0010.sql
--
-- After rollback, re-run: npm run db:migrate   to reapply.

BEGIN;

-- 1. Drop tables (order matters: forecast_jobs has no FK deps; demand_forecasts refs products only)
DROP TABLE IF EXISTS "forecast_jobs";
DROP TABLE IF EXISTS "demand_forecasts";

-- 2. (Drizzle Kit does not create a __drizzle_migrations table when using push/raw SQL;
--    reapply by re-running the SQL files directly.)

COMMIT;
