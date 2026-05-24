CREATE TABLE IF NOT EXISTS "forecast_jobs" (
	"id" uuid PRIMARY KEY NOT NULL,
	"tenant_id" integer NOT NULL,
	"requested_by" integer,
	"trigger_type" varchar(20) NOT NULL,
	"status" varchar(20) NOT NULL,
	"weeks_ahead" integer NOT NULL,
	"model_version" varchar(20) NOT NULL,
	"started_at" timestamp with time zone,
	"finished_at" timestamp with time zone,
	"lease_expires_at" timestamp with time zone,
	"generated_cnt" integer DEFAULT 0 NOT NULL,
	"skipped_cnt" integer DEFAULT 0 NOT NULL,
	"error_summary" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_forecast_jobs_tenant_status" ON "forecast_jobs" USING btree ("tenant_id","status");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_forecast_jobs_created_at" ON "forecast_jobs" USING btree ("created_at");
