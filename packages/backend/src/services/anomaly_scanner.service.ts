/**
 * AnomalyScanner — Phase 2 P2-ALT MVP
 *
 * 每小時由 Fastify onReady hook 排程執行一次。
 * 只讀 DB 狀態，寫入 anomalies 表，不觸碰同步協定。
 *
 * MVP 規則集（V2_codex § 6.2）：
 *   LONG_PENDING_ORDER    — pending 訂單超過 14 天未確認
 *   DUPLICATE_ORDER       — 同客戶 48 小時內有 2+ 筆內容相同的 pending 訂單
 *   NEGATIVE_AVAILABLE    — inventory available (onHand - reserved) < 0
 *   STOCK_CRITICAL (CRITICAL) — available < criticalStockLevel（3 天用量）→ 主管通報
 *   STOCK_ALERT    (HIGH)     — available < alertStockLevel（1 週用量）且 >= criticalStockLevel → 緊急詢源
 *   STOCK_SAFETY   (MEDIUM)   — available < minStockLevel（2 週用量）且 >= alertStockLevel → 標準補貨
 *
 * 去重邏輯：同 alertType + entityId 已有 isResolved=false 的記錄則跳過。
 * 自動解除：當觸發條件消失時，標記現有異常為 resolved。
 */

import { sql } from 'drizzle-orm';
import type { DrizzleDb } from '@/plugins/db.js';
import { type NewAnomalyForFcm, sendAnomalyNotifications } from '@/services/fcm.service.js';

// ── 嚴重度常數 ─────────────────────────────────────────────
const SEV = { CRITICAL: 'critical', HIGH: 'high', MEDIUM: 'medium' } as const;

// ── 主入口 ────────────────────────────────────────────────

export async function runAnomalyScanner(db: DrizzleDb): Promise<void> {
  const newAnomalies: NewAnomalyForFcm[] = [];
  try {
    await scanLongPendingOrders(db, newAnomalies);
    await scanDuplicateOrders(db, newAnomalies);
    await scanNegativeAvailable(db, newAnomalies);
    await scanStockCritical(db, newAnomalies);
    await scanStockAlert(db, newAnomalies);
    await scanStockSafety(db, newAnomalies);
    await scanOrderQuantitySpike(db, newAnomalies);
    await scanCustomerInactive(db, newAnomalies);
    await scanOverduePayment(db, newAnomalies);
    await scanHighValueChurnRisk(db, newAnomalies);
    await scanFrequentCancellation(db, newAnomalies);
    await autoResolveStale(db);
    // 掃描完成後，集中送出 FCM（不影響掃描結果）
    await sendAnomalyNotifications(db, newAnomalies);
  } catch (err) {
    // Scanner 失敗不應影響主業務流程，只記 log
    console.error('[AnomalyScanner] scan failed:', err);
  }
}

// ── Rule 1：LONG_PENDING_ORDER ─────────────────────────────
// pending 訂單建立超過 14 天仍未確認。

async function scanLongPendingOrders(db: DrizzleDb, out: NewAnomalyForFcm[]): Promise<void> {
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
    const message = '訂單 #' + row.id + '（' + (row.customer_name ?? '未知客戶') + '）已超過 14 天仍為待確認狀態。';
    await db.execute(sql`
      INSERT INTO anomalies
        (alert_type, severity, entity_type, entity_id, message, detail)
      VALUES (
        'LONG_PENDING_ORDER',
        ${SEV.MEDIUM},
        'sales_order',
        ${row.id},
        ${message},
        ${JSON.stringify({ orderId: row.id, customerName: row.customer_name })}::jsonb
      )
    `);
    out.push({ severity: SEV.MEDIUM, message, entityType: 'sales_order', alertType: 'LONG_PENDING_ORDER' });
  }
}

// ── Rule 1.5：DUPLICATE_ORDER ──────────────────────────────
// 同一客戶 48 小時內有 2+ 筆 pending 訂單，且品項 + 數量 fingerprint 完全一致。
// entity_type = 'customer'，每客戶一筆異常。

async function scanDuplicateOrders(db: DrizzleDb, out: NewAnomalyForFcm[]): Promise<void> {
  const rows = await db.execute(sql`
    WITH order_fingerprints AS (
      SELECT
        so.id AS order_id,
        so.customer_id,
        c.name AS customer_name,
        STRING_AGG(
          oi.product_id::text || ':' || oi.quantity::text,
          ',' ORDER BY oi.product_id, oi.quantity, oi.id
        ) AS fingerprint
      FROM sales_orders so
      JOIN order_items oi ON oi.sales_order_id = so.id
      LEFT JOIN customers c ON c.id = so.customer_id
      WHERE so.status = 'pending'
        AND so.deleted_at IS NULL
        AND so.created_at >= NOW() - INTERVAL '48 hours'
      GROUP BY so.id, so.customer_id, c.name
    ),
    duplicate_groups AS (
      SELECT
        customer_id,
        customer_name,
        fingerprint,
        ARRAY_AGG(order_id ORDER BY order_id) AS order_ids
      FROM order_fingerprints
      GROUP BY customer_id, customer_name, fingerprint
      HAVING COUNT(*) >= 2
    )
    SELECT customer_id, customer_name, fingerprint, order_ids
    FROM duplicate_groups
    WHERE customer_id NOT IN (
      SELECT entity_id FROM anomalies
      WHERE alert_type = 'DUPLICATE_ORDER'
        AND entity_type = 'customer'
        AND is_resolved = FALSE
    )
    ORDER BY customer_id
  `);

  const byCustomer = new Map<number, {
    customerName: string;
    orderIds: number[];
    groups: Array<{ fingerprint: string; orderIds: number[] }>;
  }>();

  for (const row of rows as unknown as Array<{
    customer_id: number;
    customer_name: string | null;
    fingerprint: string;
    order_ids: number[] | string;
  }>) {
    const orderIds = Array.isArray(row.order_ids)
      ? row.order_ids.map(Number)
      : String(row.order_ids).replace(/[{}]/g, '').split(',').filter(Boolean).map(Number);

    const current = byCustomer.get(row.customer_id) ?? {
      customerName: row.customer_name ?? '未知客戶',
      orderIds: [],
      groups: [],
    };

    current.orderIds.push(...orderIds);
    current.groups.push({ fingerprint: row.fingerprint, orderIds });
    byCustomer.set(row.customer_id, current);
  }

  for (const [customerId, data] of byCustomer) {
    const uniqueOrderIds = [...new Set(data.orderIds)].sort((a, b) => a - b);
    const orderList = uniqueOrderIds.map((id) => '#' + id).join('、');
    const message = '客戶「' + data.customerName + '」48 小時內出現內容完全相同的重複 pending 訂單（' + orderList + '）。';

    await db.execute(sql`
      INSERT INTO anomalies
        (alert_type, severity, entity_type, entity_id, message, detail)
      VALUES (
        'DUPLICATE_ORDER',
        ${SEV.HIGH},
        'customer',
        ${customerId},
        ${message},
        ${JSON.stringify({
          customerName: data.customerName,
          orderIds: uniqueOrderIds,
          groups: data.groups,
          windowHours: 48,
        })}::jsonb
      )
    `);
    out.push({ severity: SEV.HIGH, message, entityType: 'customer', alertType: 'DUPLICATE_ORDER' });
  }
}

// ── Rule 2：NEGATIVE_AVAILABLE ────────────────────────────
// quantity_on_hand - quantity_reserved < 0（資料一致性異常）

async function scanNegativeAvailable(db: DrizzleDb, out: NewAnomalyForFcm[]): Promise<void> {
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
    const message = '產品「' + row.product_name + '」可用庫存異常為負數（' + available + '）。onHand=' + row.quantity_on_hand + ', reserved=' + row.quantity_reserved + '。';
    await db.execute(sql`
      INSERT INTO anomalies
        (alert_type, severity, entity_type, entity_id, message, detail)
      VALUES (
        'NEGATIVE_AVAILABLE',
        ${SEV.CRITICAL},
        'inventory_item',
        ${row.id},
        ${message},
        ${JSON.stringify({
          productName: row.product_name,
          onHand: row.quantity_on_hand,
          reserved: row.quantity_reserved,
          available,
        })}::jsonb
      )
    `);
    out.push({ severity: SEV.CRITICAL, message, entityType: 'inventory_item', alertType: 'NEGATIVE_AVAILABLE' });
  }
}

// ── Rule 3a：STOCK_CRITICAL ───────────────────────────────
// available < criticalStockLevel（3 天用量）→ 主管通報
// 三層中最高優先；criticalStockLevel = 0 表示該產品不啟用此層。

async function scanStockCritical(db: DrizzleDb, out: NewAnomalyForFcm[]): Promise<void> {
  const rows = await db.execute(sql`
    SELECT ii.id, p.name AS product_name,
           ii.quantity_on_hand, ii.quantity_reserved, ii.critical_stock_level
    FROM inventory_items ii
    JOIN products p ON p.id = ii.product_id
    WHERE ii.critical_stock_level > 0
      AND (ii.quantity_on_hand - ii.quantity_reserved) < ii.critical_stock_level
      AND p.deleted_at IS NULL
      AND ii.id NOT IN (
        SELECT entity_id FROM anomalies
        WHERE alert_type = 'STOCK_CRITICAL'
          AND entity_type = 'inventory_item'
          AND is_resolved = FALSE
      )
  `);

  for (const row of rows as unknown as Array<{
    id: number; product_name: string;
    quantity_on_hand: number; quantity_reserved: number; critical_stock_level: number;
  }>) {
    const available = row.quantity_on_hand - row.quantity_reserved;
    const message = '【緊急】產品「' + row.product_name + '」庫存危急（可用 ' + available + '，危急水位 ' + row.critical_stock_level + '）。請立即通報主管。';
    await db.execute(sql`
      INSERT INTO anomalies
        (alert_type, severity, entity_type, entity_id, message, detail)
      VALUES (
        'STOCK_CRITICAL',
        ${SEV.CRITICAL},
        'inventory_item',
        ${row.id},
        ${message},
        ${JSON.stringify({
          productName: row.product_name,
          available,
          criticalStockLevel: row.critical_stock_level,
          onHand: row.quantity_on_hand,
          reserved: row.quantity_reserved,
        })}::jsonb
      )
    `);
    out.push({ severity: SEV.CRITICAL, message, entityType: 'inventory_item', alertType: 'STOCK_CRITICAL' });
  }
}

// ── Rule 3b：STOCK_ALERT ──────────────────────────────────
// available < alertStockLevel（1 週用量）且 >= criticalStockLevel → 緊急詢源
// 僅在未跌入危急區時觸發，避免與 STOCK_CRITICAL 同時存在。

async function scanStockAlert(db: DrizzleDb, out: NewAnomalyForFcm[]): Promise<void> {
  const rows = await db.execute(sql`
    SELECT ii.id, p.name AS product_name,
           ii.quantity_on_hand, ii.quantity_reserved,
           ii.alert_stock_level, ii.critical_stock_level
    FROM inventory_items ii
    JOIN products p ON p.id = ii.product_id
    WHERE ii.alert_stock_level > 0
      AND (ii.quantity_on_hand - ii.quantity_reserved) < ii.alert_stock_level
      AND (
        ii.critical_stock_level = 0
        OR (ii.quantity_on_hand - ii.quantity_reserved) >= ii.critical_stock_level
      )
      AND p.deleted_at IS NULL
      AND ii.id NOT IN (
        SELECT entity_id FROM anomalies
        WHERE alert_type = 'STOCK_ALERT'
          AND entity_type = 'inventory_item'
          AND is_resolved = FALSE
      )
  `);

  for (const row of rows as unknown as Array<{
    id: number; product_name: string;
    quantity_on_hand: number; quantity_reserved: number;
    alert_stock_level: number; critical_stock_level: number;
  }>) {
    const available = row.quantity_on_hand - row.quantity_reserved;
    const message = '【警急】產品「' + row.product_name + '」庫存偏低（可用 ' + available + '，警急水位 ' + row.alert_stock_level + '）。請啟動緊急詢源。';
    await db.execute(sql`
      INSERT INTO anomalies
        (alert_type, severity, entity_type, entity_id, message, detail)
      VALUES (
        'STOCK_ALERT',
        ${SEV.HIGH},
        'inventory_item',
        ${row.id},
        ${message},
        ${JSON.stringify({
          productName: row.product_name,
          available,
          alertStockLevel: row.alert_stock_level,
          criticalStockLevel: row.critical_stock_level,
          onHand: row.quantity_on_hand,
          reserved: row.quantity_reserved,
        })}::jsonb
      )
    `);
    out.push({ severity: SEV.HIGH, message, entityType: 'inventory_item', alertType: 'STOCK_ALERT' });
  }
}

// ── Rule 3c：STOCK_SAFETY ─────────────────────────────────
// available < minStockLevel（2 週用量）且 >= alertStockLevel → 標準補貨提醒
// 僅在未跌入警急／危急區時觸發。

async function scanStockSafety(db: DrizzleDb, out: NewAnomalyForFcm[]): Promise<void> {
  const rows = await db.execute(sql`
    SELECT ii.id, p.name AS product_name,
           ii.quantity_on_hand, ii.quantity_reserved,
           ii.min_stock_level, ii.alert_stock_level
    FROM inventory_items ii
    JOIN products p ON p.id = ii.product_id
    WHERE ii.min_stock_level > 0
      AND (ii.quantity_on_hand - ii.quantity_reserved) < ii.min_stock_level
      AND (
        ii.alert_stock_level = 0
        OR (ii.quantity_on_hand - ii.quantity_reserved) >= ii.alert_stock_level
      )
      AND p.deleted_at IS NULL
      AND ii.id NOT IN (
        SELECT entity_id FROM anomalies
        WHERE alert_type = 'STOCK_SAFETY'
          AND entity_type = 'inventory_item'
          AND is_resolved = FALSE
      )
  `);

  for (const row of rows as unknown as Array<{
    id: number; product_name: string;
    quantity_on_hand: number; quantity_reserved: number;
    min_stock_level: number; alert_stock_level: number;
  }>) {
    const available = row.quantity_on_hand - row.quantity_reserved;
    const message = '產品「' + row.product_name + '」庫存低於安全水位（可用 ' + available + '，安全水位 ' + row.min_stock_level + '）。請安排標準補貨。';
    await db.execute(sql`
      INSERT INTO anomalies
        (alert_type, severity, entity_type, entity_id, message, detail)
      VALUES (
        'STOCK_SAFETY',
        ${SEV.MEDIUM},
        'inventory_item',
        ${row.id},
        ${message},
        ${JSON.stringify({
          productName: row.product_name,
          available,
          minStockLevel: row.min_stock_level,
          alertStockLevel: row.alert_stock_level,
          onHand: row.quantity_on_hand,
          reserved: row.quantity_reserved,
        })}::jsonb
      )
    `);
    out.push({ severity: SEV.MEDIUM, message, entityType: 'inventory_item', alertType: 'STOCK_SAFETY' });
  }
}

// ── Rule 5：ORDER_QUANTITY_SPIKE ──────────────────────────
// pending 訂單某品項數量 > 近 90 天（confirmed/shipped）平均單次訂購量的 3 倍。
// entity_type = 'order_item'，每個品項一筆異常。

async function scanOrderQuantitySpike(db: DrizzleDb, out: NewAnomalyForFcm[]): Promise<void> {
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
    const message = '訂單 #' + row.sales_order_id + '（' + row.customer_name + '）的品項「' + row.product_name + '」數量 ' + row.quantity + '，為近 90 天均值的 ' + multiplier + ' 倍（均值 ' + avgQty.toFixed(1) + '）。';
    await db.execute(sql`
      INSERT INTO anomalies
        (alert_type, severity, entity_type, entity_id, message, detail)
      VALUES (
        'ORDER_QUANTITY_SPIKE',
        ${SEV.MEDIUM},
        'order_item',
        ${row.item_id},
        ${message},
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
    out.push({ severity: SEV.MEDIUM, message, entityType: 'order_item', alertType: 'ORDER_QUANTITY_SPIKE' });
  }
}

// ── Rule 6：CUSTOMER_INACTIVE ─────────────────────────────
// 曾下單的客戶超過 90 天未出現任何訂單。
// entity_type = 'customer'，每客戶一筆異常。

async function scanCustomerInactive(db: DrizzleDb, out: NewAnomalyForFcm[]): Promise<void> {
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
    const message = '客戶「' + row.customer_name + '」超過 90 天未下單（最後訂單：' + lastDate + '）。';
    await db.execute(sql`
      INSERT INTO anomalies
        (alert_type, severity, entity_type, entity_id, message, detail)
      VALUES (
        'CUSTOMER_INACTIVE',
        ${SEV.MEDIUM},
        'customer',
        ${row.customer_id},
        ${message},
        ${JSON.stringify({ customerName: row.customer_name, lastOrderAt: lastDate })}::jsonb
      )
    `);
    out.push({ severity: SEV.MEDIUM, message, entityType: 'customer', alertType: 'CUSTOMER_INACTIVE' });
  }
}

// ── Rule 7：OVERDUE_PAYMENT ───────────────────────────────
// shipped 訂單 due_date < NOW() 且 payment_status = 'unpaid'。
// entity_type = 'sales_order'，每筆訂單一條異常。

async function scanOverduePayment(db: DrizzleDb, out: NewAnomalyForFcm[]): Promise<void> {
  const rows = await db.execute(sql`
    SELECT
      so.id,
      c.name AS customer_name,
      so.due_date,
      EXTRACT(DAY FROM (NOW() - so.due_date))::int AS days_overdue,
      COALESCE(SUM(oi.subtotal), 0)::numeric(14,2) AS order_total
    FROM sales_orders so
    JOIN customers c ON c.id = so.customer_id
    LEFT JOIN order_items oi ON oi.sales_order_id = so.id
    WHERE so.payment_status = 'unpaid'
      AND so.status = 'shipped'
      AND so.due_date IS NOT NULL
      AND so.due_date < NOW()
      AND so.deleted_at IS NULL
      AND so.id NOT IN (
        SELECT entity_id FROM anomalies
        WHERE alert_type = 'OVERDUE_PAYMENT'
          AND entity_type = 'sales_order'
          AND is_resolved = FALSE
      )
    GROUP BY so.id, c.name, so.due_date
  `);

  for (const row of rows as unknown as Array<{
    id: number;
    customer_name: string;
    due_date: Date;
    days_overdue: number;
    order_total: string | number;
  }>) {
    const dueStr = new Date(row.due_date).toISOString().slice(0, 10);
    const message = '訂單 #' + row.id + '（' + row.customer_name + '）應收帳款已逾期 ' + row.days_overdue + ' 天（到期日 ' + dueStr + '，未收金額 ' + Number(row.order_total).toLocaleString() + ' 元）。';
    await db.execute(sql`
      INSERT INTO anomalies
        (alert_type, severity, entity_type, entity_id, message, detail)
      VALUES (
        'OVERDUE_PAYMENT',
        ${SEV.HIGH},
        'sales_order',
        ${row.id},
        ${message},
        ${JSON.stringify({
          orderId: row.id,
          customerName: row.customer_name,
          dueDate: dueStr,
          daysOverdue: row.days_overdue,
          orderTotal: Number(row.order_total),
        })}::jsonb
      )
    `);
    out.push({ severity: SEV.HIGH, message, entityType: 'sales_order', alertType: 'OVERDUE_PAYMENT' });
  }
}

// ── Rule 8：HIGH_VALUE_CUSTOMER_CHURN_RISK ────────────────
// 近 90 天 shipped/confirmed 累積金額在前 20% 的高價值客戶，卻在近 30 天無任何訂單。
// entity_type = 'customer'，每客戶一筆異常。

async function scanHighValueChurnRisk(db: DrizzleDb, out: NewAnomalyForFcm[]): Promise<void> {
  const rows = await db.execute(sql`
    WITH customer_ltv AS (
      SELECT
        so.customer_id,
        SUM(oi.subtotal)::numeric AS ltv_90d
      FROM sales_orders so
      JOIN order_items oi ON oi.sales_order_id = so.id
      WHERE so.status IN ('confirmed', 'shipped')
        AND so.deleted_at IS NULL
        AND so.created_at >= NOW() - INTERVAL '90 days'
      GROUP BY so.customer_id
    ),
    ltv_threshold AS (
      SELECT PERCENTILE_CONT(0.8) WITHIN GROUP (ORDER BY ltv_90d) AS p80
      FROM customer_ltv
    ),
    recent_buyers AS (
      SELECT DISTINCT customer_id
      FROM sales_orders
      WHERE deleted_at IS NULL
        AND created_at >= NOW() - INTERVAL '30 days'
    )
    SELECT
      cl.customer_id,
      c.name  AS customer_name,
      cl.ltv_90d
    FROM customer_ltv cl
    JOIN customers c      ON c.id = cl.customer_id
    CROSS JOIN ltv_threshold lt
    WHERE cl.ltv_90d >= lt.p80
      AND lt.p80 > 0
      AND c.deleted_at IS NULL
      AND cl.customer_id NOT IN (SELECT customer_id FROM recent_buyers)
      AND cl.customer_id NOT IN (
        SELECT entity_id FROM anomalies
        WHERE alert_type = 'HIGH_VALUE_CUSTOMER_CHURN_RISK'
          AND entity_type = 'customer'
          AND is_resolved = FALSE
      )
  `);

  for (const row of rows as unknown as Array<{
    customer_id: number;
    customer_name: string;
    ltv_90d: string | number;
  }>) {
    const ltvFormatted = Number(row.ltv_90d).toLocaleString('zh-TW', { maximumFractionDigits: 0 });
    const message = '高價值客戶「' + row.customer_name + '」近 30 天無訂單（近 90 天累積金額 NT$' + ltvFormatted + '，位於前 20%）。';
    await db.execute(sql`
      INSERT INTO anomalies
        (alert_type, severity, entity_type, entity_id, message, detail)
      VALUES (
        'HIGH_VALUE_CUSTOMER_CHURN_RISK',
        ${SEV.HIGH},
        'customer',
        ${row.customer_id},
        ${message},
        ${JSON.stringify({ customerName: row.customer_name, ltv90d: Number(row.ltv_90d) })}::jsonb
      )
    `);
    out.push({ severity: SEV.HIGH, message, entityType: 'customer', alertType: 'HIGH_VALUE_CUSTOMER_CHURN_RISK' });
  }
}

// ── Rule 9：FREQUENT_CANCELLATION ─────────────────────────
// 近 30 天內 cancelled 訂單數 >= 3 筆的客戶。
// entity_type = 'customer'，每客戶一筆異常。

async function scanFrequentCancellation(db: DrizzleDb, out: NewAnomalyForFcm[]): Promise<void> {
  const rows = await db.execute(sql`
    SELECT
      so.customer_id,
      c.name     AS customer_name,
      COUNT(*)::int AS cancel_count
    FROM sales_orders so
    JOIN customers c ON c.id = so.customer_id
    WHERE so.status = 'cancelled'
      AND so.deleted_at IS NULL
      AND so.updated_at >= NOW() - INTERVAL '30 days'
      AND c.deleted_at IS NULL
      AND so.customer_id NOT IN (
        SELECT entity_id FROM anomalies
        WHERE alert_type = 'FREQUENT_CANCELLATION'
          AND entity_type = 'customer'
          AND is_resolved = FALSE
      )
    GROUP BY so.customer_id, c.name
    HAVING COUNT(*) >= 3
  `);

  for (const row of rows as unknown as Array<{
    customer_id: number;
    customer_name: string;
    cancel_count: number;
  }>) {
    const message = '客戶「' + row.customer_name + '」近 30 天內已取消 ' + row.cancel_count + ' 筆訂單，請確認是否有問題。';
    await db.execute(sql`
      INSERT INTO anomalies
        (alert_type, severity, entity_type, entity_id, message, detail)
      VALUES (
        'FREQUENT_CANCELLATION',
        ${SEV.MEDIUM},
        'customer',
        ${row.customer_id},
        ${message},
        ${JSON.stringify({ customerName: row.customer_name, cancelCount: row.cancel_count })}::jsonb
      )
    `);
    out.push({ severity: SEV.MEDIUM, message, entityType: 'customer', alertType: 'FREQUENT_CANCELLATION' });
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

  // DUPLICATE_ORDER：客戶已不再有 48 小時內內容相同的重複 pending 訂單
  await db.execute(sql`
    UPDATE anomalies SET is_resolved = TRUE, resolved_at = NOW(), updated_at = NOW()
    WHERE alert_type = 'DUPLICATE_ORDER'
      AND entity_type = 'customer'
      AND is_resolved = FALSE
      AND entity_id NOT IN (
        WITH order_fingerprints AS (
          SELECT
            so.id AS order_id,
            so.customer_id,
            STRING_AGG(
              oi.product_id::text || ':' || oi.quantity::text,
              ',' ORDER BY oi.product_id, oi.quantity, oi.id
            ) AS fingerprint
          FROM sales_orders so
          JOIN order_items oi ON oi.sales_order_id = so.id
          WHERE so.status = 'pending'
            AND so.deleted_at IS NULL
            AND so.created_at >= NOW() - INTERVAL '48 hours'
          GROUP BY so.id, so.customer_id
        )
        SELECT customer_id
        FROM order_fingerprints
        GROUP BY customer_id, fingerprint
        HAVING COUNT(*) >= 2
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

  // STOCK_CRITICAL：已補充回危急水位以上，或危急水位設為 0（停用）
  await db.execute(sql`
    UPDATE anomalies SET is_resolved = TRUE, resolved_at = NOW(), updated_at = NOW()
    WHERE alert_type = 'STOCK_CRITICAL'
      AND entity_type = 'inventory_item'
      AND is_resolved = FALSE
      AND entity_id NOT IN (
        SELECT id FROM inventory_items
        WHERE critical_stock_level > 0
          AND (quantity_on_hand - quantity_reserved) < critical_stock_level
      )
  `);

  // STOCK_ALERT：已補充回警急水位以上，或已跌入危急區（升級為 STOCK_CRITICAL）
  await db.execute(sql`
    UPDATE anomalies SET is_resolved = TRUE, resolved_at = NOW(), updated_at = NOW()
    WHERE alert_type = 'STOCK_ALERT'
      AND entity_type = 'inventory_item'
      AND is_resolved = FALSE
      AND entity_id NOT IN (
        SELECT id FROM inventory_items
        WHERE alert_stock_level > 0
          AND (quantity_on_hand - quantity_reserved) < alert_stock_level
          AND (
            critical_stock_level = 0
            OR (quantity_on_hand - quantity_reserved) >= critical_stock_level
          )
      )
  `);

  // STOCK_SAFETY：已補充回安全水位以上，或已跌入警急區（升級為 STOCK_ALERT）
  await db.execute(sql`
    UPDATE anomalies SET is_resolved = TRUE, resolved_at = NOW(), updated_at = NOW()
    WHERE alert_type = 'STOCK_SAFETY'
      AND entity_type = 'inventory_item'
      AND is_resolved = FALSE
      AND entity_id NOT IN (
        SELECT id FROM inventory_items
        WHERE min_stock_level > 0
          AND (quantity_on_hand - quantity_reserved) < min_stock_level
          AND (
            alert_stock_level = 0
            OR (quantity_on_hand - quantity_reserved) >= alert_stock_level
          )
      )
  `);

  // STOCKOUT_PROLONGED（舊版規則）：清理歷史遺留記錄
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

  // OVERDUE_PAYMENT：訂單已付款（payment_status != 'unpaid'）
  await db.execute(sql`
    UPDATE anomalies SET is_resolved = TRUE, resolved_at = NOW(), updated_at = NOW()
    WHERE alert_type = 'OVERDUE_PAYMENT'
      AND entity_type = 'sales_order'
      AND is_resolved = FALSE
      AND entity_id NOT IN (
        SELECT id FROM sales_orders
        WHERE payment_status = 'unpaid'
          AND status = 'shipped'
          AND due_date IS NOT NULL
          AND due_date < NOW()
          AND deleted_at IS NULL
      )
  `);

  // HIGH_VALUE_CUSTOMER_CHURN_RISK：客戶近 30 天已重新下單
  await db.execute(sql`
    UPDATE anomalies SET is_resolved = TRUE, resolved_at = NOW(), updated_at = NOW()
    WHERE alert_type = 'HIGH_VALUE_CUSTOMER_CHURN_RISK'
      AND entity_type = 'customer'
      AND is_resolved = FALSE
      AND entity_id IN (
        SELECT DISTINCT customer_id FROM sales_orders
        WHERE deleted_at IS NULL
          AND created_at >= NOW() - INTERVAL '30 days'
      )
  `);

  // FREQUENT_CANCELLATION：近 30 天取消數已降至 2 筆以下
  await db.execute(sql`
    UPDATE anomalies SET is_resolved = TRUE, resolved_at = NOW(), updated_at = NOW()
    WHERE alert_type = 'FREQUENT_CANCELLATION'
      AND entity_type = 'customer'
      AND is_resolved = FALSE
      AND entity_id NOT IN (
        SELECT customer_id FROM sales_orders
        WHERE status = 'cancelled'
          AND deleted_at IS NULL
          AND updated_at >= NOW() - INTERVAL '30 days'
        GROUP BY customer_id
        HAVING COUNT(*) >= 3
      )
  `);
}
