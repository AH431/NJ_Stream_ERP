ALTER TABLE "inventory_items" ADD COLUMN IF NOT EXISTS "alert_stock_level" integer NOT NULL DEFAULT 0;
--> statement-breakpoint
ALTER TABLE "inventory_items" ADD COLUMN IF NOT EXISTS "critical_stock_level" integer NOT NULL DEFAULT 0;
