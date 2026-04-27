CREATE TABLE IF NOT EXISTS "customers" (
	"id" serial PRIMARY KEY NOT NULL,
	"name" varchar(255) NOT NULL,
	"contact" varchar(255),
	"tax_id" varchar(20),
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "inventory_items" (
	"id" serial PRIMARY KEY NOT NULL,
	"product_id" integer NOT NULL,
	"warehouse_id" integer DEFAULT 1 NOT NULL,
	"quantity_on_hand" integer DEFAULT 0 NOT NULL,
	"quantity_reserved" integer DEFAULT 0 NOT NULL,
	"min_stock_level" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "inventory_items_product_id_unique" UNIQUE("product_id"),
	CONSTRAINT "chk_qty_on_hand_non_negative" CHECK ("inventory_items"."quantity_on_hand" >= 0),
	CONSTRAINT "chk_qty_reserved_lte_on_hand" CHECK ("inventory_items"."quantity_reserved" <= "inventory_items"."quantity_on_hand")
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "order_items" (
	"id" serial PRIMARY KEY NOT NULL,
	"quotation_id" integer,
	"sales_order_id" integer,
	"product_id" integer NOT NULL,
	"quantity" integer NOT NULL,
	"unit_price" numeric(12, 2) NOT NULL,
	"subtotal" numeric(12, 2) NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "processed_operations" (
	"id" serial PRIMARY KEY NOT NULL,
	"operation_id" varchar(36) NOT NULL,
	"entity_type" varchar(50) NOT NULL,
	"operation_type" varchar(20) NOT NULL,
	"delta_type" varchar(20),
	"payload" jsonb NOT NULL,
	"status" varchar(20) DEFAULT 'success' NOT NULL,
	"error_message" varchar(1000),
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"processed_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "uq_operation_id" UNIQUE("operation_id")
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "products" (
	"id" serial PRIMARY KEY NOT NULL,
	"name" varchar(255) NOT NULL,
	"sku" varchar(100) NOT NULL,
	"unit_price" numeric(12, 2) NOT NULL,
	"min_stock_level" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "products_sku_unique" UNIQUE("sku")
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "quotations" (
	"id" serial PRIMARY KEY NOT NULL,
	"customer_id" integer NOT NULL,
	"created_by" integer NOT NULL,
	"total_amount" numeric(12, 2) NOT NULL,
	"tax_amount" numeric(12, 2) NOT NULL,
	"status" varchar(20) DEFAULT 'draft' NOT NULL,
	"converted_to_order_id" integer,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "sales_orders" (
	"id" serial PRIMARY KEY NOT NULL,
	"quotation_id" integer,
	"customer_id" integer NOT NULL,
	"created_by" integer NOT NULL,
	"status" varchar(20) DEFAULT 'pending' NOT NULL,
	"confirmed_at" timestamp with time zone,
	"shipped_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "users" (
	"id" serial PRIMARY KEY NOT NULL,
	"username" varchar(100) NOT NULL,
	"email" varchar(255) NOT NULL,
	"password" varchar(255) NOT NULL,
	"role" varchar(20) DEFAULT 'sales' NOT NULL,
	"is_active" boolean DEFAULT true NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "users_username_unique" UNIQUE("username"),
	CONSTRAINT "users_email_unique" UNIQUE("email")
);
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "inventory_items" ADD CONSTRAINT "inventory_items_product_id_products_id_fk" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "order_items" ADD CONSTRAINT "order_items_quotation_id_quotations_id_fk" FOREIGN KEY ("quotation_id") REFERENCES "public"."quotations"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "order_items" ADD CONSTRAINT "order_items_sales_order_id_sales_orders_id_fk" FOREIGN KEY ("sales_order_id") REFERENCES "public"."sales_orders"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "order_items" ADD CONSTRAINT "order_items_product_id_products_id_fk" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "quotations" ADD CONSTRAINT "quotations_customer_id_customers_id_fk" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "quotations" ADD CONSTRAINT "quotations_created_by_users_id_fk" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "sales_orders" ADD CONSTRAINT "sales_orders_quotation_id_quotations_id_fk" FOREIGN KEY ("quotation_id") REFERENCES "public"."quotations"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "sales_orders" ADD CONSTRAINT "sales_orders_customer_id_customers_id_fk" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "sales_orders" ADD CONSTRAINT "sales_orders_created_by_users_id_fk" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_inventory_items_product_id" ON "inventory_items" USING btree ("product_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_order_items_quotation_id" ON "order_items" USING btree ("quotation_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_order_items_sales_order_id" ON "order_items" USING btree ("sales_order_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_order_items_product_id" ON "order_items" USING btree ("product_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_processed_at" ON "processed_operations" USING btree ("processed_at");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_entity_type" ON "processed_operations" USING btree ("entity_type");