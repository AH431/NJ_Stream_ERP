-- Migration 0011: tenants table
-- Phase 4C Sprint M6.1
-- Creates the top-level tenant registry used as the FK target for all
-- business tables in migration 0012.  Inserts the default tenant (id=1)
-- so that existing rows in products, users, demand_forecasts, etc. already
-- satisfy the FK constraint that will be added in 0012.

CREATE TABLE IF NOT EXISTS "tenants" (
	"id"         serial PRIMARY KEY NOT NULL,
	"name"       varchar(100) NOT NULL,
	"slug"       varchar(50)  NOT NULL,
	"plan"       varchar(20)  DEFAULT 'basic' NOT NULL,
	"is_active"  boolean      DEFAULT true NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "uq_tenants_slug" UNIQUE("slug")
);
--> statement-breakpoint
-- Seed the default tenant so existing data can reference it.
-- ON CONFLICT DO NOTHING makes this re-runnable on staging re-applies.
INSERT INTO "tenants" ("id", "name", "slug", "plan", "is_active")
VALUES (1, 'Demo Company', 'demo', 'basic', true)
ON CONFLICT ("id") DO NOTHING;
--> statement-breakpoint
-- Reset the sequence so subsequent INSERTs get id >= 2.
SELECT setval('tenants_id_seq', GREATEST(1, (SELECT MAX(id) FROM "tenants")));
