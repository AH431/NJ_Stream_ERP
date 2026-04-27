/**
 * Analytics API — Phase 2 (P2-VIS Wave 1 + Wave 2)
 *
 * 純唯讀聚合，不觸碰同步協定，不新增任何寫入流程。
 * 資料計算交給 PostgreSQL，前端只負責渲染。
 *
 * Wave 1 端點：
 *   GET /analytics/revenue?months=N          admin, sales
 *   GET /analytics/orders/status-summary     admin, sales
 *   GET /analytics/products/top-sales        admin, warehouse
 *   GET /analytics/profit?months=N           admin
 *
 * Wave 2 端點：
 *   GET /analytics/customers/heatmap?months=N&limit=N   admin, sales
 *   GET /analytics/funnel?days=N                        admin, sales
 *   GET /analytics/inventory/trend                      admin, warehouse
 */

import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { sql } from 'drizzle-orm';
import { USER_ROLES } from '@/constants/index.js';

// ── Query param schemas ────────────────────────────────────

const RevenueQuery = z.object({
  months: z.coerce.number().int().min(1).max(24).default(6),
});

const TopSalesQuery = z.object({
  days:  z.coerce.number().int().min(1).max(365).default(30),
  limit: z.coerce.number().int().min(1).max(20).default(5),
});

const ProfitQuery = z.object({
  months: z.coerce.number().int().min(1).max(24).default(6),
});

const HeatmapQuery = z.object({
  months: z.coerce.number().int().min(1).max(12).default(6),
  limit:  z.coerce.number().int().min(1).max(20).default(10),
});

const FunnelQuery = z.object({
  days: z.coerce.number().int().min(1).max(365).default(30),
});

// ── Route handler ──────────────────────────────────────────

export default async function analyticsRoutes(app: FastifyInstance) {
  const { db } = app;

  // ── GET /analytics/revenue ─────────────────────────────
  // 月度營收：SUM(order_items.subtotal) WHERE 對應的 sales_order
  // 狀態為 confirmed 或 shipped，依月份分組，回傳近 N 個月。
  app.get('/revenue', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.ADMIN, USER_ROLES.SALES)],
  }, async (request, reply) => {
    const parse = RevenueQuery.safeParse(request.query);
    if (!parse.success) {
      return reply.status(400).send({ code: 'VALIDATION_ERROR', message: parse.error.message });
    }
    const { months } = parse.data;

    const rows = await db.execute(sql`
      SELECT
        TO_CHAR(so.created_at, 'YYYY-MM') AS month,
        COALESCE(SUM(oi.subtotal), 0)::numeric(14,2) AS revenue
      FROM sales_orders so
      JOIN order_items oi ON oi.sales_order_id = so.id
      WHERE so.status IN ('confirmed', 'shipped')
        AND so.deleted_at IS NULL
        AND so.created_at >= NOW() - (${months} || ' months')::interval
      GROUP BY month
      ORDER BY month ASC
    `);

    return reply.send({ data: rows });
  });

  // ── GET /analytics/orders/status-summary ──────────────
  // 所有未刪除訂單的狀態分佈（不限時間，呈現當前全量狀態）。
  app.get('/orders/status-summary', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.ADMIN, USER_ROLES.SALES)],
  }, async (_request, reply) => {
    const rows = await db.execute(sql`
      SELECT
        status,
        COUNT(*)::int AS count
      FROM sales_orders
      WHERE deleted_at IS NULL
      GROUP BY status
      ORDER BY status ASC
    `);

    return reply.send({ data: rows });
  });

  // ── GET /analytics/products/top-sales ─────────────────
  // 近 N 天出貨訂單中，按出貨數量排名的 Top K 產品。
  app.get('/products/top-sales', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.ADMIN, USER_ROLES.WAREHOUSE)],
  }, async (request, reply) => {
    const parse = TopSalesQuery.safeParse(request.query);
    if (!parse.success) {
      return reply.status(400).send({ code: 'VALIDATION_ERROR', message: parse.error.message });
    }
    const { days, limit } = parse.data;

    const rows = await db.execute(sql`
      SELECT
        p.id,
        p.name,
        p.sku,
        SUM(oi.quantity)::int             AS total_qty,
        COALESCE(SUM(oi.subtotal), 0)::numeric(14,2) AS total_revenue
      FROM order_items oi
      JOIN sales_orders so ON so.id = oi.sales_order_id
      JOIN products p     ON p.id  = oi.product_id
      WHERE so.status = 'shipped'
        AND so.deleted_at IS NULL
        AND p.deleted_at  IS NULL
        AND so.shipped_at >= NOW() - (${days} || ' days')::interval
      GROUP BY p.id, p.name, p.sku
      ORDER BY total_qty DESC
      LIMIT ${limit}
    `);

    return reply.send({ data: rows });
  });

  // ── GET /analytics/profit ──────────────────────────────
  // 損益摘要（Admin 專用）：月度收入、COGS、毛利、毛利率。
  // 僅計入 status='shipped' 且對應 products.cost_price IS NOT NULL 的明細。
  // 無成本的品項計入收入但不計入 COGS（毛利率欄位為 null 若全月無成本資料）。
  app.get('/profit', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.ADMIN)],
  }, async (request, reply) => {
    const parse = ProfitQuery.safeParse(request.query);
    if (!parse.success) {
      return reply.status(400).send({ code: 'VALIDATION_ERROR', message: parse.error.message });
    }
    const { months } = parse.data;

    const rows = await db.execute(sql`
      SELECT
        TO_CHAR(so.shipped_at, 'YYYY-MM')                              AS month,
        COALESCE(SUM(oi.subtotal), 0)::numeric(14,2)                   AS revenue,
        COALESCE(SUM(oi.quantity * p.cost_price)
          FILTER (WHERE p.cost_price IS NOT NULL), 0)::numeric(14,2)   AS cogs,
        CASE
          WHEN COALESCE(SUM(oi.subtotal), 0) = 0 THEN NULL
          ELSE ROUND(
            (COALESCE(SUM(oi.subtotal), 0)
              - COALESCE(SUM(oi.quantity * p.cost_price) FILTER (WHERE p.cost_price IS NOT NULL), 0))
            / COALESCE(SUM(oi.subtotal), 1) * 100, 2
          )
        END                                                            AS gross_margin_pct
      FROM sales_orders so
      JOIN order_items oi ON oi.sales_order_id = so.id
      JOIN products p     ON p.id = oi.product_id
      WHERE so.status = 'shipped'
        AND so.deleted_at IS NULL
        AND so.shipped_at IS NOT NULL
        AND so.shipped_at >= NOW() - (${months} || ' months')::interval
      GROUP BY month
      ORDER BY month ASC
    `);

    return reply.send({ data: rows });
  });

  // ── GET /analytics/customers/heatmap ──────────────────
  // Top N 客戶近 M 個月的每月下單次數（含 0 次的月份）。
  // 回傳：每客戶一列，含 monthLabels 陣列與對應 orderCount 陣列。
  app.get('/customers/heatmap', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.ADMIN, USER_ROLES.SALES)],
  }, async (request, reply) => {
    const parse = HeatmapQuery.safeParse(request.query);
    if (!parse.success) {
      return reply.status(400).send({ code: 'VALIDATION_ERROR', message: parse.error.message });
    }
    const { months, limit } = parse.data;

    // 1. 取近 M 個月的月份序列
    const monthRows = await db.execute(sql`
      SELECT TO_CHAR(m, 'YYYY-MM') AS month
      FROM generate_series(
        date_trunc('month', NOW() - (${months - 1} || ' months')::interval),
        date_trunc('month', NOW()),
        '1 month'::interval
      ) AS m
    `);
    const monthLabels = (monthRows as unknown as Array<{ month: string }>).map((r) => r.month);

    // 2. 取 Top N 客戶（依近 90 天 confirmed/shipped 訂單金額）
    const topRows = await db.execute(sql`
      SELECT so.customer_id, c.name
      FROM sales_orders so
      JOIN order_items oi ON oi.sales_order_id = so.id
      JOIN customers c    ON c.id = so.customer_id
      WHERE so.status IN ('confirmed', 'shipped')
        AND so.deleted_at IS NULL
        AND c.deleted_at IS NULL
      GROUP BY so.customer_id, c.name
      ORDER BY SUM(oi.subtotal) DESC
      LIMIT ${limit}
    `);
    const topCustomers = topRows as unknown as Array<{ customer_id: number; name: string }>;

    if (topCustomers.length === 0) {
      return reply.send({ data: [], monthLabels });
    }

    // 3. 查各客戶各月份訂單數（排除 cancelled）
    const countRows = await db.execute(sql`
      SELECT
        so.customer_id,
        TO_CHAR(so.created_at, 'YYYY-MM') AS month,
        COUNT(*)::int AS order_count
      FROM sales_orders so
      WHERE so.status != 'cancelled'
        AND so.deleted_at IS NULL
        AND so.created_at >= date_trunc('month', NOW() - (${months - 1} || ' months')::interval)
        AND so.customer_id IN (${sql.join(topCustomers.map((c) => sql`${c.customer_id}`), sql`, `)})
      GROUP BY so.customer_id, month
    `);
    const countMap = new Map<string, number>();
    for (const r of countRows as unknown as Array<{ customer_id: number; month: string; order_count: number }>) {
      countMap.set(`${r.customer_id}:${r.month}`, r.order_count);
    }

    // 4. 組裝結果：每客戶 × 每月，補 0
    const data = topCustomers.map((cust) => ({
      customerId: cust.customer_id,
      name: cust.name,
      counts: monthLabels.map((m) => countMap.get(`${cust.customer_id}:${m}`) ?? 0),
    }));

    return reply.send({ data, monthLabels });
  });

  // ── GET /analytics/funnel ──────────────────────────────
  // 近 N 天報價轉換漏斗：建立數量、已轉換、到期、進行中、平均轉換天數。
  app.get('/funnel', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.ADMIN, USER_ROLES.SALES)],
  }, async (request, reply) => {
    const parse = FunnelQuery.safeParse(request.query);
    if (!parse.success) {
      return reply.status(400).send({ code: 'VALIDATION_ERROR', message: parse.error.message });
    }
    const { days } = parse.data;

    const rows = await db.execute(sql`
      WITH base AS (
        SELECT
          q.status,
          q.created_at,
          so.created_at AS order_created_at
        FROM quotations q
        LEFT JOIN sales_orders so ON so.id = q.converted_to_order_id
        WHERE q.deleted_at IS NULL
          AND q.created_at >= NOW() - (${days} || ' days')::interval
      )
      SELECT
        COUNT(*)::int                                                          AS total_quotations,
        SUM(CASE WHEN status = 'converted' THEN 1 ELSE 0 END)::int            AS converted,
        SUM(CASE WHEN status = 'expired'   THEN 1 ELSE 0 END)::int            AS expired_count,
        SUM(CASE WHEN status IN ('draft', 'sent') THEN 1 ELSE 0 END)::int     AS pending_count,
        ROUND(AVG(
          EXTRACT(DAY FROM (order_created_at - created_at))
        ) FILTER (WHERE status = 'converted' AND order_created_at IS NOT NULL), 1) AS avg_days_to_convert
      FROM base
    `);

    const row = (rows as unknown as Array<Record<string, unknown>>)[0] ?? {};
    const total = Number(row.total_quotations ?? 0);
    const converted = Number(row.converted ?? 0);
    return reply.send({
      data: {
        totalQuotations:  total,
        converted,
        conversionRate:   total > 0 ? Number((converted / total * 100).toFixed(1)) : 0,
        expiredCount:     Number(row.expired_count ?? 0),
        pendingCount:     Number(row.pending_count ?? 0),
        avgDaysToConvert: row.avg_days_to_convert != null
          ? Number(row.avg_days_to_convert)
          : null,
      },
    });
  });

  // ── GET /analytics/inventory/trend ────────────────────
  // 近 6 個月月度出貨量（已出貨品項總數 + 涉及商品種數），作為庫存消耗趨勢指標。
  app.get('/inventory/trend', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.ADMIN, USER_ROLES.WAREHOUSE)],
  }, async (_request, reply) => {
    const rows = await db.execute(sql`
      SELECT
        TO_CHAR(so.shipped_at, 'YYYY-MM')   AS month,
        SUM(oi.quantity)::int               AS total_outbound,
        COUNT(DISTINCT oi.product_id)::int  AS active_products
      FROM order_items oi
      JOIN sales_orders so ON so.id = oi.sales_order_id
      WHERE so.status = 'shipped'
        AND so.deleted_at IS NULL
        AND so.shipped_at IS NOT NULL
        AND so.shipped_at >= NOW() - INTERVAL '6 months'
      GROUP BY month
      ORDER BY month ASC
    `);

    return reply.send({ data: rows });
  });
}
