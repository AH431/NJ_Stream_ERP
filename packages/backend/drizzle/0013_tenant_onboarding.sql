-- Migration 0013: tenant onboarding fields
-- Phase 4C Sprint M7.1 (PR-7)
--
-- Adds three optional fields to the tenants table to support the
-- self-service provisioning and onboarding flow:
--   contact_email  — primary contact / billing email for the tenant
--   timezone       — IANA timezone string; defaults to 'UTC'
--   onboarded_at   — set by the API once the tenant completes onboarding;
--                    NULL means onboarding is still in progress

ALTER TABLE "tenants"
  ADD COLUMN IF NOT EXISTS "contact_email" varchar(255);
--> statement-breakpoint
ALTER TABLE "tenants"
  ADD COLUMN IF NOT EXISTS "timezone" varchar(50) NOT NULL DEFAULT 'UTC';
--> statement-breakpoint
ALTER TABLE "tenants"
  ADD COLUMN IF NOT EXISTS "onboarded_at" timestamp with time zone;
