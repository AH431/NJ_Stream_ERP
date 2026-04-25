/**
 * Customers REST API — Issue #4
 *
 * 權限矩陣（對應 PRD §3）：
 *   GET    /customers        → sales / warehouse / admin（唯讀角色也能查）
 *   GET    /customers/:id    → sales / warehouse / admin
 *   POST   /customers        → sales / admin
 *   PUT    /customers/:id    → sales / admin
 *   DELETE /customers/:id    → admin（軟刪除）
 *
 * 軟刪除策略：DELETE 不真的移除記錄，只設 deleted_at = NOW()。
 * 所有 GET 查詢預設排除 deleted_at IS NOT NULL 的記錄。
 *
 * 時間欄位：Drizzle 以 mode:'date' 回傳 JavaScript Date，
 * Fastify JSON 序列化器自動呼叫 .toISOString()，與 API Contract 格式一致。
 */

import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { eq, isNull, and, sql } from 'drizzle-orm';
import { customers } from '@/schemas/customers.schema.js';
import { USER_ROLES } from '@/constants/index.js';

// ── RFM helpers ───────────────────────────────────────────

function rScore(daysSinceLast: number): number {
  if (daysSinceLast <= 30)  return 5;
  if (daysSinceLast <= 60)  return 4;
  if (daysSinceLast <= 90)  return 3;
  if (daysSinceLast <= 180) return 2;
  return 1;
}

function fScore(orderCount90d: number): number {
  if (orderCount90d >= 5) return 5;
  if (orderCount90d >= 3) return 4;
  if (orderCount90d >= 2) return 3;
  if (orderCount90d >= 1) return 2;
  return 1;
}

function mScore(revenue90d: number): number {
  if (revenue90d >= 50000) return 5;
  if (revenue90d >= 25000) return 4;
  if (revenue90d >= 10000) return 3;
  if (revenue90d >= 3000)  return 2;
  return 1;
}

function tier(rfm: number): string {
  if (rfm >= 12) return 'VIP';
  if (rfm >= 9)  return '活躍';
  if (rfm >= 6)  return '觀察';
  return '流失風險';
}

// ── Zod 驗證 Schema ────────────────────────────────────────

/** POST body：建立客戶 */
const CreateCustomerBody = z.object({
  name:    z.string().min(1).max(255),
  contact: z.string().max(255).optional(),
  email:   z.string().email().max(255).optional(),
  taxId:   z.string().max(20).optional(),
});

/**
 * PUT body：更新客戶（PATCH 語意 — 只更新有傳入的欄位）
 * 全部欄位 optional，至少傳一個有意義的更新才合理。
 */
const UpdateCustomerBody = z.object({
  name:    z.string().min(1).max(255).optional(),
  contact: z.string().max(255).nullable().optional(),
  email:   z.string().email().max(255).nullable().optional(),
  taxId:   z.string().max(20).nullable().optional(),
}).refine(
  (data) => Object.keys(data).length > 0,
  { message: '至少需要提供一個要更新的欄位。' },
);

/** 路由 params */
const IdParam = z.object({
  id: z.coerce.number().int().positive(),
});

// ── 路由處理 ──────────────────────────────────────────────

export default async function customersRoutes(app: FastifyInstance) {
  const { db } = app;

  // ── GET /customers ─────────────────────────────────────
  // 回傳所有未軟刪除的客戶清單，全角色可存取
  app.get('/', {
    preHandler: [app.verifyJwt],
  }, async (_request, reply) => {
    const result = await db
      .select()
      .from(customers)
      .where(isNull(customers.deletedAt))
      .orderBy(customers.id);

    return reply.status(200).send(result);
  });

  // ── GET /customers/rfm ─────────────────────────────────
  // 回傳所有客戶的 RFM 分數與分級。
  // 純 server-side 計算，不寫回 customers 表。
  // 權限：sales / admin（倉管無 CRM 權限）
  app.get('/rfm', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.SALES, USER_ROLES.ADMIN)],
  }, async (_request, reply) => {
    const rows = await db.execute(sql`
      WITH order_revenue AS (
        SELECT
          so.customer_id,
          so.status,
          so.created_at,
          COALESCE(SUM(oi.subtotal), 0)::numeric AS order_total
        FROM sales_orders so
        LEFT JOIN order_items oi ON oi.sales_order_id = so.id
        WHERE so.deleted_at IS NULL
        GROUP BY so.customer_id, so.id, so.status, so.created_at
      ),
      metrics AS (
        SELECT
          c.id,
          c.name,
          c.contact,
          c.email,
          COALESCE(
            EXTRACT(DAY FROM NOW() - MAX(orv.created_at))::int,
            9999
          )                                                   AS days_since_last_order,
          COUNT(CASE
            WHEN orv.status IN ('confirmed', 'shipped')
              AND orv.created_at >= NOW() - INTERVAL '90 days'
            THEN 1
          END)::int                                           AS order_count_90d,
          COALESCE(SUM(CASE
            WHEN orv.status IN ('confirmed', 'shipped')
              AND orv.created_at >= NOW() - INTERVAL '90 days'
            THEN orv.order_total ELSE 0
          END), 0)::numeric                                   AS revenue_90d,
          COALESCE(SUM(CASE
            WHEN orv.status IN ('confirmed', 'shipped')
            THEN orv.order_total ELSE 0
          END), 0)::numeric                                   AS ltv
        FROM customers c
        LEFT JOIN order_revenue orv ON orv.customer_id = c.id
        WHERE c.deleted_at IS NULL
        GROUP BY c.id, c.name, c.contact, c.email
      )
      SELECT * FROM metrics
      ORDER BY name ASC
    `);

    const result = (rows as unknown as Array<{
      id: number;
      name: string;
      contact: string | null;
      email: string | null;
      days_since_last_order: number;
      order_count_90d: number;
      revenue_90d: string;
      ltv: string;
    }>).map((row) => {
      const r = rScore(row.days_since_last_order);
      const f = fScore(row.order_count_90d);
      const m = mScore(Number(row.revenue_90d));
      const rfm = r + f + m;
      return {
        customerId:          row.id,
        name:                row.name,
        contact:             row.contact,
        email:               row.email,
        rScore:              r,
        fScore:              f,
        mScore:              m,
        rfmScore:            rfm,
        tier:                tier(rfm),
        daysSinceLastOrder:  row.days_since_last_order,
        orderCount90d:       row.order_count_90d,
        revenue90d:          Number(row.revenue_90d),
        ltv:                 Number(row.ltv),
      };
    });

    return reply.status(200).send(result);
  });

  // ── GET /customers/:id ─────────────────────────────────
  app.get('/:id', {
    preHandler: [app.verifyJwt],
  }, async (request, reply) => {
    const parsed = IdParam.safeParse(request.params);
    if (!parsed.success) {
      return reply.status(400).send({ code: 'VALIDATION_ERROR', message: 'id 必須為正整數。' });
    }

    const [customer] = await db
      .select()
      .from(customers)
      .where(and(eq(customers.id, parsed.data.id), isNull(customers.deletedAt)));

    if (!customer) {
      return reply.status(404).send({ code: 'NOT_FOUND', message: '找不到此客戶。' });
    }

    return reply.status(200).send(customer);
  });

  // ── POST /customers ────────────────────────────────────
  // 建立新客戶；sales 和 admin 可執行
  app.post('/', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.SALES, USER_ROLES.ADMIN)],
  }, async (request, reply) => {
    const parsed = CreateCustomerBody.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        code: 'VALIDATION_ERROR',
        message: parsed.error.issues[0]?.message ?? '請求格式錯誤。',
      });
    }

    const { name, contact, email, taxId } = parsed.data;
    const [created] = await db
      .insert(customers)
      .values({ name, contact: contact ?? null, email: email ?? null, taxId: taxId ?? null })
      .returning();

    return reply.status(201).send(created);
  });

  // ── PUT /customers/:id ─────────────────────────────────
  // 更新客戶資料（PATCH 語意，只覆寫有傳入的欄位）
  // sales 和 admin 可執行；倉管唯讀。
  //
  // 注意：LWW（Last-Write-Wins）衝突解決發生在 sync/push 路由，
  // 此端點為直接線上操作，不做 updatedAt 比對。
  app.put('/:id', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.SALES, USER_ROLES.ADMIN)],
  }, async (request, reply) => {
    const paramParsed = IdParam.safeParse(request.params);
    if (!paramParsed.success) {
      return reply.status(400).send({ code: 'VALIDATION_ERROR', message: 'id 必須為正整數。' });
    }

    const bodyParsed = UpdateCustomerBody.safeParse(request.body);
    if (!bodyParsed.success) {
      return reply.status(400).send({
        code: 'VALIDATION_ERROR',
        message: bodyParsed.error.issues[0]?.message ?? '請求格式錯誤。',
      });
    }

    // 只將有傳入的欄位加入 SET 子句（PATCH 語意）
    const updates: Partial<typeof bodyParsed.data & { updatedAt: Date }> = {
      ...bodyParsed.data,
      updatedAt: new Date(),  // 強制更新時間戳（$onUpdate 備援）
    };

    const [updated] = await db
      .update(customers)
      .set(updates)
      .where(and(eq(customers.id, paramParsed.data.id), isNull(customers.deletedAt)))
      .returning();

    if (!updated) {
      return reply.status(404).send({ code: 'NOT_FOUND', message: '找不到此客戶或已被刪除。' });
    }

    return reply.status(200).send(updated);
  });

  // ── DELETE /customers/:id ──────────────────────────────
  // 軟刪除：設定 deleted_at，不實際移除記錄
  // 只有 admin 可執行（PRD §3 權限矩陣）
  app.delete('/:id', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.ADMIN)],
  }, async (request, reply) => {
    const parsed = IdParam.safeParse(request.params);
    if (!parsed.success) {
      return reply.status(400).send({ code: 'VALIDATION_ERROR', message: 'id 必須為正整數。' });
    }

    const [deleted] = await db
      .update(customers)
      .set({ deletedAt: new Date() })
      .where(and(eq(customers.id, parsed.data.id), isNull(customers.deletedAt)))
      .returning();

    if (!deleted) {
      return reply.status(404).send({ code: 'NOT_FOUND', message: '找不到此客戶或已被刪除。' });
    }

    // 204 No Content：軟刪除成功，無需回傳 body
    return reply.status(204).send();
  });
}
