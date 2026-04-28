/**
 * AR (Accounts Receivable) API — Phase 2 (P2-ACC)
 *
 * Admin 專用。計算基準：sales_orders.payment_status = 'unpaid' 且 status = 'shipped'。
 * due_date 由後端在訂單確認（confirmed）時自動填入：結帳期限為確認日次月月底。
 *
 * 端點：
 *   GET /ar/summary   → 未收總覽（aging buckets）
 *   GET /ar/orders    → 未收訂單明細列表
 *   PUT /ar/orders/:id/payment  → 標記付款（paid / written_off）
 */

import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { sql, eq, and, isNull } from 'drizzle-orm';
import { salesOrders } from '@/schemas/sales_orders.schema.js';
import { USER_ROLES, PAYMENT_STATUSES } from '@/constants/index.js';

const MarkPaymentBody = z.object({
  paymentStatus: z.enum([PAYMENT_STATUSES.PAID, PAYMENT_STATUSES.WRITTEN_OFF]),
  paidAt: z.string().datetime().optional(),
});

export default async function arRoutes(app: FastifyInstance) {
  const { db } = app;

  // ── GET /ar/summary ────────────────────────────────────────
  // 回傳 aging buckets：0-30 / 31-60 / 61-90 / 90+ 天逾期金額
  app.get('/summary', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.ADMIN)],
  }, async (_request, reply) => {
    const rows = await db.execute(sql`
      WITH unpaid AS (
        SELECT
          so.id,
          so.due_date,
          COALESCE(SUM(oi.subtotal), 0)::numeric(14,2) AS order_total
        FROM sales_orders so
        LEFT JOIN order_items oi ON oi.sales_order_id = so.id
        WHERE so.payment_status = 'unpaid'
          AND so.status = 'shipped'
          AND so.deleted_at IS NULL
        GROUP BY so.id, so.due_date
      )
      SELECT
        COALESCE(SUM(order_total), 0)::numeric(14,2)                                                    AS total_unpaid,
        COALESCE(SUM(order_total) FILTER (WHERE due_date < NOW()), 0)::numeric(14,2)                    AS total_overdue,
        COALESCE(SUM(order_total) FILTER (WHERE due_date >= NOW() OR due_date IS NULL), 0)::numeric(14,2) AS total_current,
        COALESCE(SUM(order_total) FILTER (
          WHERE due_date < NOW() AND due_date >= NOW() - INTERVAL '30 days'
        ), 0)::numeric(14,2) AS bucket_0_30,
        COALESCE(SUM(order_total) FILTER (
          WHERE due_date < NOW() - INTERVAL '30 days' AND due_date >= NOW() - INTERVAL '60 days'
        ), 0)::numeric(14,2) AS bucket_31_60,
        COALESCE(SUM(order_total) FILTER (
          WHERE due_date < NOW() - INTERVAL '60 days' AND due_date >= NOW() - INTERVAL '90 days'
        ), 0)::numeric(14,2) AS bucket_61_90,
        COALESCE(SUM(order_total) FILTER (
          WHERE due_date < NOW() - INTERVAL '90 days'
        ), 0)::numeric(14,2) AS bucket_90_plus,
        COUNT(*)::int AS unpaid_order_count
      FROM unpaid
    `);

    return reply.send({ data: rows[0] ?? {} });
  });

  // ── GET /ar/orders ─────────────────────────────────────────
  // 未收訂單列表（含客戶名稱、應收金額、逾期天數）
  app.get('/orders', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.ADMIN)],
  }, async (_request, reply) => {
    const rows = await db.execute(sql`
      SELECT
        so.id,
        c.name            AS customer_name,
        so.shipped_at,
        so.due_date,
        GREATEST(0, EXTRACT(DAY FROM (NOW() - so.due_date)))::int AS days_overdue,
        COALESCE(SUM(oi.subtotal), 0)::numeric(14,2)              AS order_total
      FROM sales_orders so
      JOIN customers c ON c.id = so.customer_id
      LEFT JOIN order_items oi ON oi.sales_order_id = so.id
      WHERE so.payment_status = 'unpaid'
        AND so.status = 'shipped'
        AND so.deleted_at IS NULL
      GROUP BY so.id, c.name, so.shipped_at, so.due_date
      ORDER BY so.due_date ASC NULLS LAST
    `);

    return reply.send({ data: rows });
  });

  // ── PUT /ar/orders/:id/payment ─────────────────────────────
  // 標記付款狀態（paid / written_off）
  app.put('/orders/:id/payment', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.ADMIN)],
  }, async (request, reply) => {
    const id = parseInt((request.params as { id: string }).id, 10);
    if (isNaN(id)) {
      return reply.status(400).send({ code: 'VALIDATION_ERROR', message: 'Invalid order id' });
    }

    const parse = MarkPaymentBody.safeParse(request.body);
    if (!parse.success) {
      return reply.status(400).send({ code: 'VALIDATION_ERROR', message: parse.error.message });
    }
    const { paymentStatus, paidAt } = parse.data;

    const [updated] = await db
      .update(salesOrders)
      .set({
        paymentStatus,
        paidAt: paymentStatus === PAYMENT_STATUSES.PAID
          ? (paidAt ? new Date(paidAt) : new Date())
          : null,
        updatedAt: new Date(),
      })
      .where(and(eq(salesOrders.id, id), isNull(salesOrders.deletedAt)))
      .returning({ id: salesOrders.id, paymentStatus: salesOrders.paymentStatus });

    if (!updated) {
      return reply.status(404).send({ code: 'NOT_FOUND', message: 'Order not found' });
    }

    return reply.send({ data: updated });
  });
}
