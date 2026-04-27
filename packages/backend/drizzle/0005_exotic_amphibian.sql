ALTER TABLE "customers" ADD COLUMN "payment_terms_days" integer DEFAULT 30 NOT NULL;--> statement-breakpoint
ALTER TABLE "products" ADD COLUMN "cost_price" numeric(12, 2);--> statement-breakpoint
ALTER TABLE "sales_orders" ADD COLUMN "payment_status" varchar(20) DEFAULT 'unpaid' NOT NULL;--> statement-breakpoint
ALTER TABLE "sales_orders" ADD COLUMN "paid_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "sales_orders" ADD COLUMN "due_date" timestamp with time zone;