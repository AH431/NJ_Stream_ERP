-- Migration 0014: add spq, moq to products; add line_notes to order_items
--
-- spq (Standard Package Quantity / 標準包裝量):
--   每組/整盤/整捲的零件數量。下單數量必須為 spq 的整數倍。
--   預設值 1 = 以單件下單（向下相容既有資料）。
--
-- moq (Minimum Order Quantity / 最小訂購量):
--   最少需下幾「組」。實際最小下單件數 = moq × spq。
--   預設值 1。
--
-- line_notes (行備註):
--   報價單明細的整盤說明，例如「每組 5,000 pcs」，
--   讓客戶清楚換算實際零件總量。

ALTER TABLE "products"
  ADD COLUMN IF NOT EXISTS "spq" integer NOT NULL DEFAULT 1;
--> statement-breakpoint
ALTER TABLE "products"
  ADD COLUMN IF NOT EXISTS "moq" integer NOT NULL DEFAULT 1;
--> statement-breakpoint
ALTER TABLE "order_items"
  ADD COLUMN IF NOT EXISTS "line_notes" varchar(500);
