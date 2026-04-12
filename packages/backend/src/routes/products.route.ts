/**
 * Products REST API — Issue #4
 *
 * 權限矩陣（對應 PRD §3）：
 *   GET    /products         → sales / warehouse / admin（全部唯讀）
 *   GET    /products/:id     → sales / warehouse / admin
 *   POST   /products         → admin 專屬
 *   PUT    /products/:id     → admin 專屬
 *   DELETE /products/:id     → admin 專屬（軟刪除）
 *
 * unitPrice：PostgreSQL numeric 欄位，Drizzle 以 string 回傳（如 "158000.00"），
 * 直接串到 JSON 不需轉換，與前端 DecimalConverter 格式完全一致。
 */

import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { eq, isNull, and } from 'drizzle-orm';
import { products } from '@/schemas/products.schema.js';
import { USER_ROLES } from '@/constants/index.js';

// ── Zod 驗證 Schema ────────────────────────────────────────

/** POST body：建立產品 */
const CreateProductBody = z.object({
  name:          z.string().min(1).max(255),
  sku:           z.string().min(1).max(100),
  // unitPrice 以字串接收，後端存入 numeric；格式由前端 DecimalConverter 保證
  unitPrice:     z.string().regex(/^\d+(\.\d{1,2})?$/, 'unitPrice 格式應為數字或最多兩位小數，如 "158000.00"'),
  minStockLevel: z.number().int().min(0).optional().default(0),
});

/**
 * PUT body：更新產品（PATCH 語意 — 只更新有傳入的欄位）
 */
const UpdateProductBody = z.object({
  name:          z.string().min(1).max(255).optional(),
  sku:           z.string().min(1).max(100).optional(),
  unitPrice:     z.string().regex(/^\d+(\.\d{1,2})?$/, 'unitPrice 格式應為數字或最多兩位小數').optional(),
  minStockLevel: z.number().int().min(0).optional(),
}).refine(
  (data) => Object.keys(data).length > 0,
  { message: '至少需要提供一個要更新的欄位。' },
);

/** 路由 params */
const IdParam = z.object({
  id: z.coerce.number().int().positive(),
});

// ── 路由處理 ──────────────────────────────────────────────

export default async function productsRoutes(app: FastifyInstance) {
  const { db } = app;

  // ── GET /products ──────────────────────────────────────
  // 回傳所有未軟刪除的產品，全角色可存取
  app.get('/', {
    preHandler: [app.verifyJwt],
  }, async (_request, reply) => {
    const result = await db
      .select()
      .from(products)
      .where(isNull(products.deletedAt))
      .orderBy(products.id);

    return reply.status(200).send(result);
  });

  // ── GET /products/:id ──────────────────────────────────
  app.get('/:id', {
    preHandler: [app.verifyJwt],
  }, async (request, reply) => {
    const parsed = IdParam.safeParse(request.params);
    if (!parsed.success) {
      return reply.status(400).send({ code: 'VALIDATION_ERROR', message: 'id 必須為正整數。' });
    }

    const [product] = await db
      .select()
      .from(products)
      .where(and(eq(products.id, parsed.data.id), isNull(products.deletedAt)));

    if (!product) {
      return reply.status(404).send({ code: 'NOT_FOUND', message: '找不到此產品。' });
    }

    return reply.status(200).send(product);
  });

  // ── POST /products ─────────────────────────────────────
  // 建立新產品；僅 admin 可操作（PRD §3：產品管理 = admin 讀寫）
  app.post('/', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.ADMIN)],
  }, async (request, reply) => {
    const parsed = CreateProductBody.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        code: 'VALIDATION_ERROR',
        message: parsed.error.issues[0]?.message ?? '請求格式錯誤。',
      });
    }

    const { name, sku, unitPrice, minStockLevel } = parsed.data;

    try {
      const [created] = await db
        .insert(products)
        .values({ name, sku, unitPrice, minStockLevel })
        .returning();

      return reply.status(201).send(created);
    } catch (err: unknown) {
      // PostgreSQL 唯一約束違反：sku 重複
      const e = err as { code?: string };
      if (e.code === '23505') {
        return reply.status(409).send({
          code: 'DATA_CONFLICT',
          message: `SKU "${sku}" 已存在，請使用不同的 SKU。`,
        });
      }
      throw err; // 其他 DB 錯誤交由 Fastify 全域錯誤處理
    }
  });

  // ── PUT /products/:id ──────────────────────────────────
  // 更新產品資料；僅 admin 可操作
  app.put('/:id', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.ADMIN)],
  }, async (request, reply) => {
    const paramParsed = IdParam.safeParse(request.params);
    if (!paramParsed.success) {
      return reply.status(400).send({ code: 'VALIDATION_ERROR', message: 'id 必須為正整數。' });
    }

    const bodyParsed = UpdateProductBody.safeParse(request.body);
    if (!bodyParsed.success) {
      return reply.status(400).send({
        code: 'VALIDATION_ERROR',
        message: bodyParsed.error.issues[0]?.message ?? '請求格式錯誤。',
      });
    }

    const updates = {
      ...bodyParsed.data,
      updatedAt: new Date(),
    };

    try {
      const [updated] = await db
        .update(products)
        .set(updates)
        .where(and(eq(products.id, paramParsed.data.id), isNull(products.deletedAt)))
        .returning();

      if (!updated) {
        return reply.status(404).send({ code: 'NOT_FOUND', message: '找不到此產品或已被刪除。' });
      }

      return reply.status(200).send(updated);
    } catch (err: unknown) {
      const e = err as { code?: string };
      if (e.code === '23505') {
        return reply.status(409).send({
          code: 'DATA_CONFLICT',
          message: 'SKU 已被其他產品使用，請換一個 SKU。',
        });
      }
      throw err;
    }
  });

  // ── DELETE /products/:id ───────────────────────────────
  // 軟刪除：設定 deleted_at，不實際移除記錄；僅 admin 可操作
  app.delete('/:id', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.ADMIN)],
  }, async (request, reply) => {
    const parsed = IdParam.safeParse(request.params);
    if (!parsed.success) {
      return reply.status(400).send({ code: 'VALIDATION_ERROR', message: 'id 必須為正整數。' });
    }

    const [deleted] = await db
      .update(products)
      .set({ deletedAt: new Date() })
      .where(and(eq(products.id, parsed.data.id), isNull(products.deletedAt)))
      .returning();

    if (!deleted) {
      return reply.status(404).send({ code: 'NOT_FOUND', message: '找不到此產品或已被刪除。' });
    }

    return reply.status(204).send();
  });
}
