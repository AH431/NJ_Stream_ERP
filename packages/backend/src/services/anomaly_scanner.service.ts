/**
 * AnomalyScanner — Phase 2 P2-ALT MVP
 *
 * 每小時由 Fastify onReady hook 排程執行一次。
 * 只讀 DB 狀態，寫入 anomalies 表，不觸碰同步協定。
 *
 * MVP 規則集（V2_codex § 6.2）：
 *   LONG_PENDING_ORDER    — pending 訂單超過 14 天未確認
 *   NEGATIVE_AVAILABLE    — inventory available (onHand - reserved) < 0
 *   STOCKOUT_PROLONGED    — available < minStockLevel（minStockLevel > 0）
 *
 * 去重邏輯：同 alertType + entityId 已有 isResolved=false 的記錄則跳過。
 * 自動解除：當觸發條件消失時，標記現有異常為 resolved。
 */

import { sql } from 'drizzle-orm';
import type { DrizzleDb } from '@/plugins/db.js';

// ── 嚴重度常數 ─────────────────────────────────────────────
const SEV = { CRITICAL: 'critical', HIGH: 'high', MEDIUM: 'medium' } as const;

// ── 主入口 ────────────────────────────────────────────────

export async function runAnomalyScanner(db: DrizzleDb): Promise<void> {
  try {
    await scanLongPendingOrders(db);
    await scanNegativeAvailable(db);
    await scanStockoutProlonged(db);
    await autoResolveStale(db);
  } catch (err) {
    // Scanner 失敗不應影響主業務流程，只記 log
    console.error('[AnomalyScanner] scan failed:', err);
  }
}

// ── Rule 1：LONG_PENDING_ORDER ─────────────────────────────
// pending 訂單建立超過 14 天仍未確認。

async function scanLongPendingOrders(db: DrizzleDb): Promise<void> {
  const rows = await db.execute(sql`
    SELECT so.id, c.name AS customer_name
    FROM sales_orders so
    LEFT JOIN customers c ON c.id = so.customer_id
    WHERE so.status = 'pending'
      AND so.deleted_at IS NULL
      AND so.created_at < NOW() - INTERVAL '14 days'
      AND so.id NOT IN (
        SELECT entity_id FROM anomalies
        WHERE alert_type = 'LONG_PENDING_ORDER'
          AND entity_type = 'sales_order'
          AND is_resolved = FALSE
      )
  `);

  for (const row of rows as unknown as Array<{ id: number; customer_name: string | null }>) {
    await db.execute(sql`
      INSERT INTO anomalies
        (alert_type, severity, entity_type, entity_id, message, detail)
      VALUES (
        'LONG_PENDING_ORDER',
        ${SEV.MEDIUM},
        'sales_order',
        ${row.id},
        ${'訂單 #' + row.id + '（' + (row.customer_name ?? '未知客戶') + '）已超過 14 天仍為待確認狀態。'},
        ${JSON.stringify({ orderId: row.id, customerName: row.customer_name })}::jsonb
      )
    `);
  }
}

// ── Rule 2：NEGATIVE_AVAILABLE ────────────────────────────
// quantity_on_hand - quantity_reserved < 0（資料一致性異常）

async function scanNegativeAvailable(db: DrizzleDb): Promise<void> {
  const rows = await db.execute(sql`
    SELECT ii.id, p.name AS product_name,
           ii.quantity_on_hand, ii.quantity_reserved
    FROM inventory_items ii
    JOIN products p ON p.id = ii.product_id
    WHERE ii.quantity_on_hand - ii.quantity_reserved < 0
      AND p.deleted_at IS NULL
      AND ii.id NOT IN (
        SELECT entity_id FROM anomalies
        WHERE alert_type = 'NEGATIVE_AVAILABLE'
          AND entity_type = 'inventory_item'
          AND is_resolved = FALSE
      )
  `);

  for (const row of rows as unknown as Array<{
    id: number; product_name: string;
    quantity_on_hand: number; quantity_reserved: number;
  }>) {
    const available = row.quantity_on_hand - row.quantity_reserved;
    await db.execute(sql`
      INSERT INTO anomalies
        (alert_type, severity, entity_type, entity_id, message, detail)
      VALUES (
        'NEGATIVE_AVAILABLE',
        ${SEV.CRITICAL},
        'inventory_item',
        ${row.id},
        ${'產品「' + row.product_name + '」可用庫存異常為負數（' + available + '）。onHand=' + row.quantity_on_hand + ', reserved=' + row.quantity_reserved + '。'},
        ${JSON.stringify({
          productName: row.product_name,
          onHand: row.quantity_on_hand,
          reserved: row.quantity_reserved,
          available,
        })}::jsonb
      )
    `);
  }
}

// ── Rule 3：STOCKOUT_PROLONGED ────────────────────────────
// available < minStockLevel（且 minStockLevel > 0）

async function scanStockoutProlonged(db: DrizzleDb): Promise<void> {
  const rows = await db.execute(sql`
    SELECT ii.id, p.name AS product_name,
           ii.quantity_on_hand, ii.quantity_reserved, ii.min_stock_level
    FROM inventory_items ii
    JOIN products p ON p.id = ii.product_id
    WHERE ii.min_stock_level > 0
      AND (ii.quantity_on_hand - ii.quantity_reserved) < ii.min_stock_level
      AND p.deleted_at IS NULL
      AND ii.id NOT IN (
        SELECT entity_id FROM anomalies
        WHERE alert_type = 'STOCKOUT_PROLONGED'
          AND entity_type = 'inventory_item'
          AND is_resolved = FALSE
      )
  `);

  for (const row of rows as unknown as Array<{
    id: number; product_name: string;
    quantity_on_hand: number; quantity_reserved: number; min_stock_level: number;
  }>) {
    const available = row.quantity_on_hand - row.quantity_reserved;
    await db.execute(sql`
      INSERT INTO anomalies
        (alert_type, severity, entity_type, entity_id, message, detail)
      VALUES (
        'STOCKOUT_PROLONGED',
        ${SEV.CRITICAL},
        'inventory_item',
        ${row.id},
        ${'產品「' + row.product_name + '」庫存低於安全水位（可用 ' + available + '，安全水位 ' + row.min_stock_level + '）。'},
        ${JSON.stringify({
          productName: row.product_name,
          available,
          minStockLevel: row.min_stock_level,
          onHand: row.quantity_on_hand,
          reserved: row.quantity_reserved,
        })}::jsonb
      )
    `);
  }
}

// ── 自動解除：條件消失則標記 resolved ─────────────────────

async function autoResolveStale(db: DrizzleDb): Promise<void> {
  // LONG_PENDING_ORDER：訂單不再是 pending 或已刪除
  await db.execute(sql`
    UPDATE anomalies SET is_resolved = TRUE, resolved_at = NOW(), updated_at = NOW()
    WHERE alert_type = 'LONG_PENDING_ORDER'
      AND entity_type = 'sales_order'
      AND is_resolved = FALSE
      AND entity_id NOT IN (
        SELECT id FROM sales_orders
        WHERE status = 'pending' AND deleted_at IS NULL
      )
  `);

  // NEGATIVE_AVAILABLE：available 已恢復 >= 0
  await db.execute(sql`
    UPDATE anomalies SET is_resolved = TRUE, resolved_at = NOW(), updated_at = NOW()
    WHERE alert_type = 'NEGATIVE_AVAILABLE'
      AND entity_type = 'inventory_item'
      AND is_resolved = FALSE
      AND entity_id NOT IN (
        SELECT id FROM inventory_items
        WHERE quantity_on_hand - quantity_reserved < 0
      )
  `);

  // STOCKOUT_PROLONGED：庫存已補充回安全水位
  await db.execute(sql`
    UPDATE anomalies SET is_resolved = TRUE, resolved_at = NOW(), updated_at = NOW()
    WHERE alert_type = 'STOCKOUT_PROLONGED'
      AND entity_type = 'inventory_item'
      AND is_resolved = FALSE
      AND entity_id NOT IN (
        SELECT id FROM inventory_items
        WHERE min_stock_level > 0
          AND (quantity_on_hand - quantity_reserved) < min_stock_level
      )
  `);
}
