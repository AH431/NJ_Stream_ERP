CREATE TABLE IF NOT EXISTS "anomalies" (
	"id" serial PRIMARY KEY NOT NULL,
	"alert_type" varchar(64) NOT NULL,
	"severity" varchar(16) NOT NULL,
	"entity_type" varchar(32) NOT NULL,
	"entity_id" integer NOT NULL,
	"message" text NOT NULL,
	"detail" jsonb,
	"is_resolved" boolean DEFAULT false NOT NULL,
	"resolved_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_anomalies_unresolved" ON "anomalies" USING btree ("is_resolved","severity");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_anomalies_entity" ON "anomalies" USING btree ("entity_type","entity_id");