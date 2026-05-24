CREATE TABLE IF NOT EXISTS "demand_forecasts" (
	"id" serial PRIMARY KEY NOT NULL,
	"product_id" integer NOT NULL,
	"tenant_id" integer NOT NULL,
	"week_start" date NOT NULL,
	"forecast_qty" numeric(10,2) NOT NULL,
	"lower_bound" numeric(10,2),
	"upper_bound" numeric(10,2),
	"model_version" varchar(20) DEFAULT 'prophet-v1' NOT NULL,
	"generated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"run_id" uuid NOT NULL,
	CONSTRAINT "uq_demand_forecasts_tenant_product_week_model" UNIQUE("tenant_id","product_id","week_start","model_version")
);
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "demand_forecasts" ADD CONSTRAINT "demand_forecasts_product_id_products_id_fk" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_demand_forecasts_tenant_product" ON "demand_forecasts" USING btree ("tenant_id","product_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_demand_forecasts_week_start" ON "demand_forecasts" USING btree ("week_start");
