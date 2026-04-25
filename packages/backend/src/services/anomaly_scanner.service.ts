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
    await scanDuplicateOrders(db);
    await scanOrderQuantitySpike(db);
    await scanCustomerInactive(db);
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

// ── Rule 4：DUPLICATE_ORDER ───────────────────────────────
// 同一客戶 48 小時內存在 2+ 筆 pending 訂單，且品項 / 數量完全相同。
// entity_type = 'customer'，每客戶一筆異常（不重複插入）。

async function scanDuplicateOrders(db: DrizzleDb): Promise<void> {
  const rows = await db.execute(sql`
    WITH order_fingerprints AS (
      SELECT
        so.id           AS order_id,
        so.customer_id,
        array_agg(oi.product_id ORDER BY oi.product_id ASC, oi.quantity ASC) AS product_ids,
        array_agg(oi.quantity   ORDER BY oi.product_id ASC, oi.quantity ASC) AS quantities
      FROM sales_orders so
      JOIN order_items oi ON oi.sales_order_id = so.id
      WHERE so.status   = 'pending'
        AND so.deleted_at IS NULL
        AND so.created_at >= NOW() - INTERVAL '48 hours'
      GROUP BY so.id, so.customer_id
    ),
    dup_groups AS (
      SELECT
        customer_id,
        array_agg(order_id ORDER BY order_id) AS order_ids
      FROM order_fingerprints
      GROUP BY customer_id, product_ids, quantities
      HAVING COUNT(*) >= 2
    )
    SELECT
      dg.customer_id,
      c.name AS customer_name,
      dg.order_ids
    FROM dup_groups dg
    JOIN customers c ON c.id = dg.customer_id
    WHERE dg.customer_id NOT IN (
      SELECT entity_id FROM anomalies
      WHERE alert_type = 'DUPLICATE_ORDER'
        AND entity_type = 'customer'
        AND is_resolved = FALSE
    )
  `);

  for (const row of rows as unknown as Array<{
    customer_id: number;
    customer_name: string;
    order_ids: number[];
  }>) {
    const orderList = row.order_ids.map((id) => '#' + id).join('、');
    await db.execute(sql`
      INSERT INTO anomalies
        (alert_type, severity, entity_type, entity_id, message, detail)
      VALUES (
        'DUPLICATE_ORDER',
        ${SEV.HIGH},
        'customer',
        ${row.customer_id},
        ${'客戶「' + row.customer_name + '」48 小時內出現內容完全相同的重複 pending 訂單（' + orderList + '）。'},
        ${JSON.stringify({ customerName: row.customer_name, orderIds: row.order_ids })}::jsonb
      )
    `);
  }
}

// ── Rule 5：ORDER_QUANTITY_SPIKE ──────────────────────────
// pending 訂單某品項數量 > 近 90 天（confirmed/shipped）平均單次訂購量的 3 倍。
// entity_type = 'order_item'，每個品項一筆異常。

async function scanOrderQuantitySpike(db: DrizzleDb): Promise<void> {
  const rows = await db.execute(sql`
    WITH avg_qty AS (
      SELECT
        oi.product_id,
        AVG(oi.quantity)::numeric AS avg_order_qty
      FROM order_items oi
      JOIN sales_orders so ON so.id = oi.sales_order_id
      WHERE so.status IN ('confirmed', 'shipped')
        AND so.deleted_at IS NULL
        AND oi.created_at >= NOW() - INTERVAL '90 days'
      GROUP BY oi.product_id
    )
    SELECT
      oi.id              AS item_id,
      oi.sales_order_id,
      oi.quantity,
      aq.avg_order_qty,
      p.name             AS product_name,
      c.name             AS customer_name
    FROM order_items oi
    JOIN avg_qty aq     ON aq.product_id = oi.product_id
    JOIN sales_orders so ON so.id = oi.sales_order_id
    JOIN products p     ON p.id = oi.product_id
    JOIN customers c    ON c.id = so.customer_id
    WHERE so.status = 'pending'
      AND so.deleted_at IS NULL
      AND oi.quantity > aq.avg_order_qty * 3
      AND oi.id NOT IN (
        SELECT entity_id FROM anomalies
        WHERE alert_type = 'ORDER_QUANTITY_SPIKE'
          AND entity_type = 'order_item'
          AND is_resolved = FALSE
      )
  `);

  for (const row of rows as unknown as Array<{
    item_id: number;
    sales_order_id: number;
    quantity: number;
    avg_order_qty: string | number;
    product_name: string;
    customer_name: string;
  }>) {
    const avgQty = Number(row.avg_order_qty);
    const multiplier = (row.quantity / avgQty).toFixed(1);
    await db.execute(sql`
      INSERT INTO anomalies
        (alert_type, severity, entity_type, entity_id, message, detail)
      VALUES (
        'ORDER_QUANTITY_SPIKE',
        ${SEV.MEDIUM},
        'order_item',
        ${row.item_id},
        ${'訂單 #' + row.sales_order_id + '（' + row.customer_name + '）的品項「' + row.product_name + '」數量 ' + row.quantity + '，為近 90 天均值的 ' + multiplier + ' 倍（均值 ' + avgQty.toFixed(1) + '）。'},
        ${JSON.stringify({
          orderId: row.sales_order_id,
          productName: row.product_name,
          customerName: row.customer_name,
          quantity: row.quantity,
          avgOrderQty: avgQty,
          multiplier: Number(multiplier),
        })}::jsonb
      )
    `);
  }
}

// ── Rule 6：CUSTOMER_INACTIVE ─────────────────────────────
// 曾下單的客戶超過 90 天未出現任何訂單。
// entity_type = 'customer'，每客戶一筆異常。

async function scanCustomerInactive(db: DrizzleDb): Promise<void> {
  const rows = await db.execute(sql`
    SELECT
      c.id             AS customer_id,
      c.name           AS customer_name,
      MAX(so.created_at) AS last_order_at
    FROM customers c
    JOIN sales_orders so ON so.customer_id = c.id
      AND so.deleted_at IS NULL
    WHERE c.deleted_at IS NULL
      AND c.id NOT IN (
        SELECT entity_id FROM anomalies
        WHERE alert_type = 'CUSTOMER_INACTIVE'
          AND entity_type = 'customer'
          AND is_resolved = FALSE
      )
    GROUP BY c.id, c.name
    HAVING MAX(so.created_at) < NOW() - INTERVAL '90 days'
  `);

  for (const row of rows as unknown as Array<{
    customer_id: number;
    customer_name: string;
    last_order_at: Date;
  }>) {
    const lastDate = new Date(row.last_order_at).toISOString().slice(0, 10);
    await db.execute(sql`
      INSERT INTO anomalies
        (alert_type, severity, entity_type, entity_id, message, detail)
      VALUES (
        'CUSTOMER_INACTIVE',
        ${SEV.MEDIUM},
        'customer',
        ${row.customer_id},
        ${'客戶「' + row.customer_name + '」超過 90 天未下單（最後訂單：' + lastDate + '）。'},
        ${JSON.stringify({ customerName: row.customer_name, lastOrderAt: lastDate })}::jsonb
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

  // DUPLICATE_ORDER：客戶不再有重複內容的 pending 訂單（48h 窗口內）
  await db.execute(sql`
    UPDATE anomalies SET is_resolved = TRUE, resolved_at = NOW(), updated_at = NOW()
    WHERE alert_type = 'DUPLICATE_ORDER'
      AND entity_type = 'customer'
      AND is_resolved = FALSE
      AND entity_id NOT IN (
        SELECT DISTINCT customer_id
        FROM (
          SELECT
            so.customer_id,
            array_agg(oi.product_id ORDER BY oi.product_id ASC, oi.quantity ASC) AS product_ids,
            array_agg(oi.quantity   ORDER BY oi.product_id ASC, oi.quantity ASC) AS quantities
          FROM sales_orders so
          JOIN order_items oi ON oi.sales_order_id = so.id
          WHERE so.status   = 'pending'
            AND so.deleted_at IS NULL
            AND so.created_at >= NOW() - INTERVAL '48 hours'
          GROUP BY so.id, so.customer_id
        ) f
        GROUP BY f.customer_id, f.product_ids, f.quantities
        HAVING COUNT(*) >= 2
      )
  `);

  // ORDER_QUANTITY_SPIKE：parent 訂單不再是 pending
  await db.execute(sql`
    UPDATE anomalies SET is_resolved = TRUE, resolved_at = NOW(), updated_at = NOW()
    WHERE alert_type = 'ORDER_QUANTITY_SPIKE'
      AND entity_type = 'order_item'
      AND is_resolved = FALSE
      AND entity_id NOT IN (
        SELECT oi.id FROM order_items oi
        JOIN sales_orders so ON so.id = oi.sales_order_id
        WHERE so.status = 'pending' AND so.deleted_at IS NULL
      )
  `);

  // CUSTOMER_INACTIVE：客戶已重新下單（90 天內有訂單）
  await db.execute(sql`
    UPDATE anomalies SET is_resolved = TRUE, resolved_at = NOW(), updated_at = NOW()
    WHERE alert_type = 'CUSTOMER_INACTIVE'
      AND entity_type = 'customer'
      AND is_resolved = FALSE
      AND entity_id IN (
        SELECT DISTINCT customer_id FROM sales_orders
        WHERE deleted_at IS NULL
          AND created_at >= NOW() - INTERVAL '90 days'
      )
  `);
}
