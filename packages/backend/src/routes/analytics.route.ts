/**
 * Analytics API — Phase 2 (P2-VIS Wave 1)
 *
 * 純唯讀聚合，不觸碰同步協定，不新增任何寫入流程。
 * 資料計算交給 PostgreSQL，前端只負責渲染。
 *
 * 端點：
 *   GET /analytics/revenue?months=N          admin, sales
 *   GET /analytics/orders/status-summary     admin, sales
 *   GET /analytics/products/top-sales        admin, warehouse
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
}
